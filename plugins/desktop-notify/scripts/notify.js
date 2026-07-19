#!/usr/bin/env node
'use strict';

/*
 * desktop-notify — cross-platform hook dispatcher.
 *
 * Invoked by Copilot CLI hooks as:
 *   node "${PLUGIN_ROOT}/scripts/notify.js" --event <permission|idle|stop>
 *
 * Reads the hook payload (JSON) from stdin and shows a native desktop
 * notification when Copilot is waiting on the user. It never throws into the
 * caller: every failure path exits 0 so a notification problem can never
 * disrupt a Copilot turn.
 *
 * Order of checks (deliberate):
 *   1. subordinate / nested process skip
 *   2. SSH / headless skip (unless overridden)
 *   3. focus check (skip if the user's terminal is focused)
 *   4. atomic debounce claim (keyed by session + event)
 *   5. dispatch the OS-native notification
 *
 * The debounce lock is claimed only AFTER the focus check so a suppressed
 * notification does not "eat" the lock and hide the next legitimate one.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync, execFileSync } = require('child_process');

const SCRIPT_DIR = __dirname;
const BACKEND_TIMEOUT_MS = 8000;

// ---------------------------------------------------------------------------
// Config (environment variables)
// ---------------------------------------------------------------------------
const DEBOUNCE_SECONDS = (() => {
  const raw = process.env.COPILOT_NOTIFY_DEBOUNCE;
  if (raw === undefined || raw === '') return 10;
  const n = parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : 10;
})();
const ALWAYS_NOTIFY = !!process.env.COPILOT_NOTIFY_ALWAYS;
const DEBUG = !!process.env.COPILOT_NOTIFY_DEBUG;

// Priority is used only for documentation of intent; the debounce is keyed per
// event so an urgent "permission" is never suppressed by an earlier "idle".
const EVENT_META = {
  permission: { title: 'Copilot needs permission', body: 'Copilot is waiting for you to approve an action.' },
  idle: { title: 'Copilot is waiting', body: 'Copilot is waiting for your input.' },
  stop: { title: 'Copilot finished', body: 'Copilot finished this turn.' },
};

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------
function debugLog(message) {
  if (!DEBUG) return;
  try {
    const dir = path.join(os.tmpdir(), 'copilot_notify_debug');
    fs.mkdirSync(dir, { recursive: true });
    const line = `[${new Date().toISOString()}] ${message}\n`;
    fs.appendFileSync(path.join(dir, 'notify.log'), line);
  } catch (_) {
    /* debug logging must never throw */
  }
}

function quietExit(reason) {
  debugLog(`exit: ${reason}`);
  process.exit(0);
}

function parseEventArg() {
  const argv = process.argv.slice(2);
  const idx = argv.indexOf('--event');
  if (idx !== -1 && argv[idx + 1]) return argv[idx + 1].toLowerCase();
  return null;
}

function readStdin() {
  try {
    const raw = fs.readFileSync(0, 'utf8');
    if (!raw || !raw.trim()) return {};
    return JSON.parse(raw);
  } catch (_) {
    return {};
  }
}

function isWsl() {
  if (process.platform !== 'linux') return false;
  try {
    const rel = os.release().toLowerCase();
    if (rel.includes('microsoft') || rel.includes('wsl')) return true;
  } catch (_) { /* ignore */ }
  return !!process.env.WSL_DISTRO_NAME;
}

function isHeadlessSession() {
  // Skip when there is no interactive desktop to receive the notification.
  if (process.env.SSH_CONNECTION || process.env.SSH_TTY || process.env.SSH_CLIENT) return true;
  if (process.platform === 'linux' && !isWsl() && !process.env.DISPLAY && !process.env.WAYLAND_DISPLAY) {
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Focus detection
// ---------------------------------------------------------------------------
// Returns true when the user's terminal appears to be the focused window and
// we should therefore stay quiet. Best-effort per platform; on any error or
// unsupported platform it returns false (i.e. we notify).
function terminalIsFocused(cwd) {
  try {
    if (process.platform === 'win32' || isWsl()) {
      // Delegate to the PowerShell helper which knows how to inspect Windows
      // Terminal tabs; it prints "FOCUSED" when the terminal is in front.
      const ps = powershellExe();
      if (!ps) return false;
      const res = spawnSync(
        ps,
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', winPath(path.join(SCRIPT_DIR, 'notify.ps1')),
          '-Mode', 'focus', '-WorkingDirectory', cwd || ''],
        { timeout: BACKEND_TIMEOUT_MS, encoding: 'utf8' }
      );
      return (res.stdout || '').trim().toUpperCase().includes('FOCUSED');
    }

    if (process.platform === 'darwin') {
      // App-level only: is a known terminal application frontmost?
      const script =
        'tell application "System Events" to get name of first application process whose frontmost is true';
      const res = spawnSync('osascript', ['-e', script], { timeout: BACKEND_TIMEOUT_MS, encoding: 'utf8' });
      const front = (res.stdout || '').trim();
      const terminals = ['Terminal', 'iTerm2', 'iTerm', 'Alacritty', 'kitty', 'WezTerm', 'Warp', 'Hyper', 'Ghostty', 'Code'];
      return terminals.some((t) => front === t);
    }
  } catch (_) {
    return false;
  }
  // Linux: reliable active-window detection is not available dependency-free.
  return false;
}

// ---------------------------------------------------------------------------
// Debounce (atomic, per session + event)
// ---------------------------------------------------------------------------
function debounced(sessionId, event) {
  if (DEBOUNCE_SECONDS <= 0) return false;
  const key = crypto
    .createHash('sha1')
    .update(`${sessionId || 'nosession'}::${event}`)
    .digest('hex')
    .slice(0, 16);
  const lockFile = path.join(os.tmpdir(), `copilot_notify_${key}.lock`);
  try {
    // Exclusive create is atomic: only the first racer succeeds.
    const fd = fs.openSync(lockFile, 'wx');
    fs.closeSync(fd);
    return false; // acquired — proceed to notify
  } catch (err) {
    if (err && err.code === 'EEXIST') {
      let ageSec = Infinity;
      try {
        ageSec = (Date.now() - fs.statSync(lockFile).mtimeMs) / 1000;
      } catch (_) { /* treat as expired */ }
      if (ageSec < DEBOUNCE_SECONDS) return true; // within window — suppress
      try { fs.utimesSync(lockFile, new Date(), new Date()); } catch (_) { /* ignore */ }
      return false;
    }
    // Unexpected FS error — don't let it suppress a notification.
    return false;
  }
}

// ---------------------------------------------------------------------------
// Windows helpers
// ---------------------------------------------------------------------------
function powershellExe() {
  // Prefer Windows PowerShell (WinRT/toast is best supported there), fall back
  // to pwsh. On WSL, call the Windows-side powershell.exe.
  const candidates = process.platform === 'win32'
    ? ['powershell.exe', 'pwsh.exe', 'pwsh']
    : ['powershell.exe', 'pwsh']; // WSL: powershell.exe is on the interop PATH
  for (const c of candidates) {
    try {
      const probe = spawnSync(c, ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'], {
        timeout: 4000,
        encoding: 'utf8',
      });
      if (probe.status === 0) return c;
    } catch (_) { /* try next */ }
  }
  return null;
}

function winPath(p) {
  // When invoking Windows PowerShell from WSL, translate /mnt/c/... to C:\...
  if (!isWsl()) return p;
  try {
    const out = execFileSync('wslpath', ['-w', p], { encoding: 'utf8', timeout: 4000 });
    return out.trim() || p;
  } catch (_) {
    return p;
  }
}

// ---------------------------------------------------------------------------
// Notification backends
// ---------------------------------------------------------------------------
function notifyWindows(title, body) {
  const ps = powershellExe();
  if (!ps) return quietExit('powershell not found');
  // Title/body are passed as discrete arguments (no shell string building) so
  // quotes/newlines in dynamic text cannot break the command.
  const res = spawnSync(
    ps,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', winPath(path.join(SCRIPT_DIR, 'notify.ps1')),
      '-Mode', 'notify', '-Title', title, '-Body', body],
    { timeout: BACKEND_TIMEOUT_MS, encoding: 'utf8', windowsHide: true }
  );
  debugLog(`windows notify status=${res.status} err=${(res.stderr || '').trim()}`);
}

function notifyMac(title, body) {
  // Static AppleScript that reads title/body from argv — no source interpolation.
  const script =
    'on run argv\n' +
    '  display notification (item 2 of argv) with title (item 1 of argv)\n' +
    'end run';
  spawnSync('osascript', ['-e', script, title, body], { timeout: BACKEND_TIMEOUT_MS, encoding: 'utf8' });
  debugLog('mac notify dispatched');
}

function notifyLinux(title, body) {
  // `--` terminates option parsing so a title/body beginning with '-' is safe.
  const res = spawnSync('notify-send', ['-a', 'Copilot CLI', '--', title, body], {
    timeout: BACKEND_TIMEOUT_MS,
    encoding: 'utf8',
  });
  if (res.error && res.error.code === 'ENOENT') {
    debugLog('linux: notify-send not installed');
  }
}

function dispatch(title, body) {
  try {
    if (isWsl()) return notifyWindows(title, body);
    switch (process.platform) {
      case 'win32':
        return notifyWindows(title, body);
      case 'darwin':
        return notifyMac(title, body);
      case 'linux':
        return notifyLinux(title, body);
      default:
        return quietExit(`unsupported platform ${process.platform}`);
    }
  } catch (err) {
    return quietExit(`dispatch error: ${err && err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
function main() {
  const event = parseEventArg();
  if (!event || !EVENT_META[event]) return quietExit(`unknown event arg: ${event}`);

  // Nested / subordinate Copilot processes must not notify.
  if (process.env.COPILOT_SUBORDINATE || process.env.CLAUDE_SUBORDINATE) {
    return quietExit('subordinate process');
  }

  const payload = readStdin();
  const sessionId = payload.session_id || '';
  const cwd = payload.cwd || process.cwd();

  // Sanity-check the declared event against the payload when possible.
  if (payload.hook_event_name === 'Stop' && event !== 'stop') {
    debugLog(`event arg "${event}" disagrees with hook_event_name "Stop"`);
  }

  if (isHeadlessSession() && !ALWAYS_NOTIFY) return quietExit('headless/ssh session');

  if (!ALWAYS_NOTIFY && terminalIsFocused(cwd)) return quietExit('terminal focused');

  if (debounced(sessionId, event)) return quietExit('debounced');

  const meta = EVENT_META[event];
  dispatch(meta.title, meta.body);
  process.exit(0);
}

try {
  main();
} catch (err) {
  // Absolute backstop: never surface an error to the hook runner.
  quietExit(`unhandled: ${err && err.message}`);
}
