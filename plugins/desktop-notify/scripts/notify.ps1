<#
.SYNOPSIS
    Windows backend for the desktop-notify Copilot CLI plugin.

.DESCRIPTION
    Two modes:
      -Mode focus  : prints "FOCUSED" to stdout when the user's terminal appears
                     to be the foreground window (so the caller stays quiet).
                     Prints nothing otherwise.
      -Mode notify : shows a native toast (Windows.UI.Notifications). If the
                     toast cannot be shown (WinRT unavailable / not registered),
                     falls back to a NotifyIcon balloon so a notification still
                     appears without any third-party dependency.

    This script never writes to stderr in a way that should fail the caller and
    always exits 0.

.NOTES
    Title/Body arrive as discrete parameters, so no dynamic text is ever
    interpolated into a command string. Toast XML text is XML-escaped.
#>
[CmdletBinding()]
param(
    [ValidateSet('focus', 'notify')]
    [string]$Mode = 'notify',
    [string]$Title = 'Copilot',
    [string]$Body = 'Copilot needs your attention.',
    [string]$WorkingDirectory = ''
)

$ErrorActionPreference = 'Stop'

function Test-TerminalFocused {
    param([string]$WorkingDir)

    try {
        Add-Type @"
            using System;
            using System.Runtime.InteropServices;
            using System.Text;
            public class DesktopNotifyWin32 {
                [DllImport("user32.dll")]
                public static extern IntPtr GetForegroundWindow();
                [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
                public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
            }
"@
    } catch {
        return $false
    }

    if (-not $WorkingDir) { $WorkingDir = (Get-Location).Path }

    $foregroundWindow = [DesktopNotifyWin32]::GetForegroundWindow()
    $className = New-Object System.Text.StringBuilder 256
    [DesktopNotifyWin32]::GetClassName($foregroundWindow, $className, 256) | Out-Null
    $windowClass = $className.ToString()

    # Only Windows Terminal exposes inspectable tabs; other terminals/windows
    # are treated as "not focused" (so we notify), matching voice-notify.
    if ($windowClass -ne 'CASCADIA_HOSTING_WINDOW_CLASS') { return $false }

    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

        $termWin = [System.Windows.Automation.AutomationElement]::FromHandle($foregroundWindow)

        $tabCond = New-Object System.Windows.Automation.PropertyCondition `
            ([System.Windows.Automation.AutomationElement]::ControlTypeProperty,
             [System.Windows.Automation.ControlType]::Tab)
        $tab = $termWin.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
        if (-not $tab) { return $false }

        $listCond = New-Object System.Windows.Automation.PropertyCondition `
            ([System.Windows.Automation.AutomationElement]::ControlTypeProperty,
             [System.Windows.Automation.ControlType]::List)
        $listView = $tab.FindFirst([System.Windows.Automation.TreeScope]::Children, $listCond)
        if (-not $listView) { return $false }

        $tabItemCond = New-Object System.Windows.Automation.PropertyCondition `
            ([System.Windows.Automation.AutomationElement]::ControlTypeProperty,
             [System.Windows.Automation.ControlType]::TabItem)
        $items = $listView.FindAll([System.Windows.Automation.TreeScope]::Children, $tabItemCond)

        foreach ($item in $items) {
            $pat = $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
            if ($pat.Current.IsSelected) {
                $selectedTabName = $item.Current.Name

                # A running command (sparkle U+2733 or " - " separator) means the
                # user is actively watching this terminal.
                if ($selectedTabName -match '\u2733' -or $selectedTabName -match ' - ') { return $true }

                if ($selectedTabName -match '([A-Z]:\\[^\s]+)') {
                    $selectedDir = $Matches[1].TrimEnd('\')
                    $normalizedWorkingDir = $WorkingDir.TrimEnd('\')
                    if ($normalizedWorkingDir -like "$selectedDir*") { return $true }
                }
                break
            }
        }
    } catch {
        # If inspection fails, be conservative and treat as focused so we don't
        # spam a user who is in fact watching Windows Terminal.
        return $true
    }

    return $false
}

function Show-Toast {
    param([string]$Title, [string]$Body)

    # AppId of an app already registered in the Start menu makes the toast
    # reliable; PowerShell's AUMID is present on Windows 10/11.
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

    $safeTitle = [System.Security.SecurityElement]::Escape($Title)
    $safeBody = [System.Security.SecurityElement]::Escape($Body)

    $xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$safeTitle</text>
      <text>$safeBody</text>
    </binding>
  </visual>
</toast>
"@

    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
    $notifier.Show($toast)
}

function Show-BalloonFallback {
    param([string]$Title, [string]$Body)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    try {
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon.Visible = $true
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText = $Body
        $notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        $notifyIcon.ShowBalloonTip(6000)
        # Keep the icon alive briefly so the balloon actually renders.
        Start-Sleep -Milliseconds 900
    } finally {
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
    }
}

try {
    if ($Mode -eq 'focus') {
        if (Test-TerminalFocused -WorkingDir $WorkingDirectory) { Write-Output 'FOCUSED' }
        exit 0
    }

    try {
        Show-Toast -Title $Title -Body $Body
    } catch {
        try {
            Show-BalloonFallback -Title $Title -Body $Body
        } catch {
            # Give up quietly — a failed notification must never disrupt Copilot.
        }
    }
} catch {
    # Absolute backstop.
}

exit 0
