# Desktop Notify Plugin

Native desktop notifications when Copilot CLI is **waiting on you** — so you can step away and get
pulled back the moment Copilot needs something.

## Overview

`desktop-notify` registers Copilot CLI **hooks** that fire a desktop notification when:

- **Copilot needs permission** — a tool/command approval is pending (`Notification` / `permission_prompt`).
- **Copilot is waiting** — it's idle, waiting for your next input, question, or clarification
  (`Notification` / `idle_prompt`).
- **Copilot finished** — the current turn completed (`Stop`).

It uses each OS's **built-in** notifier (no third-party modules to install) and — where supported —
**stays quiet while your terminal is focused**, so you're only interrupted when you're looking away.

There is no skill or slash command to invoke: once installed, it works automatically in the
background via hooks.

## How it works

The plugin declares hooks in [`hooks/hooks.json`](hooks/hooks.json). Each hook runs the
cross-platform dispatcher [`scripts/notify.js`](scripts/notify.js) with an `--event` argument:

```
node "${PLUGIN_ROOT}/scripts/notify.js" --event <permission|idle|stop>
```

The dispatcher reads the hook payload from stdin and then, in order:

1. **Skips nested/subordinate** Copilot processes (`COPILOT_SUBORDINATE` / `CLAUDE_SUBORDINATE`).
2. **Skips headless/SSH** sessions (no desktop to notify) unless overridden.
3. **Skips when your terminal is focused** (unless overridden).
4. **Debounces** — an atomic, per-`session + event` temp lock prevents duplicate spam (for example,
   several background tasks each emitting `Stop`).
5. **Dispatches** the OS-native notification.

Hooks run `async` and every backend runs with a hard timeout and **fails quietly** — a notification
problem can never disrupt or block a Copilot turn.

## Platform support

| Platform | Notification | Focus suppression |
|----------|--------------|-------------------|
| **Windows** | Toast via `Windows.UI.Notifications`, with a `NotifyIcon` balloon fallback | ✅ Full — foreground window + Windows Terminal active-tab inspection |
| **macOS** | `osascript` `display notification` | ⚠️ Best-effort — app-level only (can't target a specific terminal window/tab) |
| **Linux** | `notify-send` (quiet no-op if not installed / no D-Bus) | ❌ Not supported (reliable active-window detection isn't available dependency-free, especially on Wayland) → always notifies |
| **WSL** | Routed to the Windows toast backend | ✅ Uses the Windows path |

> On Windows, the toast is attributed to PowerShell (it reuses PowerShell's registered app identity
> so the toast reliably reaches the Action Center without any setup). If the toast API is
> unavailable, a tray balloon is shown instead.

## Configuration

Configure via environment variables (for example in your shell profile or Copilot `env` settings):

| Variable | Default | Description |
|----------|---------|-------------|
| `COPILOT_NOTIFY_DEBOUNCE` | `10` | Minimum seconds between notifications for the same session + event. Set `0` to disable debouncing. |
| `COPILOT_NOTIFY_ALWAYS` | unset | If set (to any value), disables focus and headless suppression — always notify. |
| `COPILOT_NOTIFY_DEBUG` | unset | If set, writes debug logs to `%TEMP%\copilot_notify_debug\notify.log` (or `$TMPDIR/copilot_notify_debug/notify.log`). |

## Install

```bash
# From the dev-skills marketplace
copilot plugin install desktop-notify@dev-skills

# Or directly from this repo's subdirectory
copilot plugin install cottonstartiet/dev-skills:plugins/desktop-notify
```

Verify it loaded with `/env` (look for the `desktop-notify` hooks) or `copilot plugin list`.

### Try it locally (development)

```bash
copilot plugin install ./plugins/desktop-notify
```

Re-run the install command to pick up local edits (plugin components are cached after install).

## Testing without a Copilot session

You can exercise the dispatcher directly by piping a fake hook payload:

```powershell
# Windows PowerShell — force a toast even while the terminal is focused
$env:COPILOT_NOTIFY_ALWAYS = "1"
'{"session_id":"test","cwd":"."}' | node plugins/desktop-notify/scripts/notify.js --event permission
```

```bash
# macOS / Linux
COPILOT_NOTIFY_ALWAYS=1 echo '{"session_id":"test","cwd":"."}' \
  | node plugins/desktop-notify/scripts/notify.js --event idle
```

## Troubleshooting

- **No notification on Windows:** ensure notifications aren't disabled in Windows Settings →
  System → Notifications; the plugin falls back to a tray balloon if the toast API fails. Enable
  `COPILOT_NOTIFY_DEBUG=1` and check the log.
- **Notifies while I'm watching the terminal:** full focus suppression only works in **Windows
  Terminal** on Windows. Other terminals / platforms notify more eagerly by design.
- **No notification on Linux:** install a notification daemon and `notify-send` (usually
  `libnotify-bin`); headless/SSH sessions are skipped by default.
- **Too many notifications from background tasks:** increase `COPILOT_NOTIFY_DEBOUNCE`.

## License

MIT
