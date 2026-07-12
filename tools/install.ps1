<#
.SYNOPSIS
    Menu-driven installer for the dev-skills command-line tools.

.DESCRIPTION
    Discovers every tool under this 'tools/' directory (each tool has a tool.json
    manifest), shows a menu with a short overview of each, and "installs" the
    selected tool(s) by adding a small function to your PowerShell profile so the
    tool's command (e.g. 'tr') is available in every new session.

    The function is written between clearly marked, per-command fences so installs
    are idempotent and can be cleanly removed with -Uninstall.

.PARAMETER Tool
    Install/uninstall only the named tool (non-interactive). e.g. -Tool worktree

.PARAMETER All
    Install/uninstall every discovered tool (non-interactive).

.PARAMETER Uninstall
    Remove the selected tool command(s) from your profile instead of installing.

.PARAMETER Yes
    Skip confirmation prompts (assume "yes").

.PARAMETER ProfilePath
    Override the PowerShell profile file to edit. Defaults to
    $PROFILE.CurrentUserAllHosts. Mainly for testing.

.EXAMPLE
    pwsh -NoProfile -File tools/install.ps1
.EXAMPLE
    pwsh -NoProfile -File tools/install.ps1 -Tool worktree -Yes
.EXAMPLE
    pwsh -NoProfile -File tools/install.ps1 -All -Uninstall -Yes
#>
[CmdletBinding()]
param(
    [string]$Tool,
    [switch]$All,
    [switch]$Uninstall,
    [switch]$Yes,
    [string]$ProfilePath
)

$ErrorActionPreference = 'Stop'
$ToolsRoot = $PSScriptRoot

function Write-Info { param([string]$Message) Write-Host $Message }
function Write-Ok   { param([string]$Message) Write-Host "OK  $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "WARN  $Message" -ForegroundColor Yellow }
function Fail { param([string]$Message) Write-Host "ERROR  $Message" -ForegroundColor Red; exit 1 }

# Discover every tool: a subdirectory of $ToolsRoot containing a valid tool.json.
function Get-Tools {
    $tools = @()
    $seenCommands = @{}
    foreach ($dir in (Get-ChildItem -LiteralPath $ToolsRoot -Directory | Sort-Object Name)) {
        $manifest = Join-Path $dir.FullName 'tool.json'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        try { $meta = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json }
        catch { Write-Warn2 "Skipping '$($dir.Name)': tool.json is not valid JSON ($($_.Exception.Message))."; continue }
        foreach ($field in 'name', 'command', 'script') {
            if ([string]::IsNullOrWhiteSpace($meta.$field)) {
                Write-Warn2 "Skipping '$($dir.Name)': tool.json is missing required field '$field'."
                $meta = $null; break
            }
        }
        if (-not $meta) { continue }
        if ($meta.command -notmatch '^[A-Za-z][A-Za-z0-9_.-]*$') {
            Write-Warn2 "Skipping '$($meta.name)': command '$($meta.command)' is not a valid command name (use letters, digits, '.', '_', '-')."
            continue
        }
        if ($seenCommands.ContainsKey($meta.command)) {
            Write-Warn2 "Skipping '$($meta.name)': command '$($meta.command)' already claimed by '$($seenCommands[$meta.command])'."
            continue
        }
        $scriptPath = Join-Path $dir.FullName $meta.script
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            Write-Warn2 "Skipping '$($meta.name)': script '$($meta.script)' not found."; continue
        }
        $seenCommands[$meta.command] = $meta.name
        $tools += [pscustomobject]@{
            Name       = $meta.name
            Command    = $meta.command
            Summary    = if ($meta.summary) { $meta.summary } else { '' }
            Version    = if ($meta.version) { $meta.version } else { '' }
            ScriptPath = (Get-Item -LiteralPath $scriptPath).FullName
        }
    }
    $tools
}

function Resolve-ProfilePath {
    if (-not [string]::IsNullOrWhiteSpace($ProfilePath)) { return $ProfilePath }
    # AllHosts so the command works across pwsh, VS Code terminal, etc.
    $PROFILE.CurrentUserAllHosts
}

function Get-ManagedBlock {
    param([Parameter(Mandatory)][pscustomobject]$ToolObj)
    $cmd = $ToolObj.Command
    # Single-quote the path for the PS literal; escape any embedded single quotes.
    $escaped = $ToolObj.ScriptPath.Replace("'", "''")
    @"
# >>> dev-skills tool: $cmd >>>
function $cmd { & pwsh -NoProfile -File '$escaped' @args }
# <<< dev-skills tool: $cmd <<<
"@
}

# Remove a previously-installed managed block for a command (idempotent).
# Fences are matched at line start only, so marker-like text elsewhere is untouched.
function Remove-ManagedBlock {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content, [Parameter(Mandatory)][string]$Command)
    $c = [regex]::Escape($Command)
    $pattern = "(?ms)^# >>> dev-skills tool: $c >>>.*?^# <<< dev-skills tool: $c <<<[^\r\n]*\r?\n?"
    $result = $Content -replace $pattern, ''
    # Collapse any run of 3+ newlines left behind into a single blank line.
    ($result -replace "(\r?\n){3,}", "`n`n").Trim()
}

function Read-ProfileContent {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw) }
    ''
}

function Write-ProfileContent {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    # Back up an existing non-empty profile before rewriting it.
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -gt 0) {
        Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force
    }
    $text = $Content.TrimEnd()
    if ($text.Length -gt 0) { $text += "`n" }
    Set-Content -LiteralPath $Path -Value $text -NoNewline -Encoding utf8
}

function Install-Tool {
    param([Parameter(Mandatory)][pscustomobject]$ToolObj, [Parameter(Mandatory)][string]$Path)
    $existing = Get-Command -Name $ToolObj.Command -ErrorAction SilentlyContinue
    if ($existing -and $existing.CommandType -ne 'Function') {
        Write-Warn2 "A '$($ToolObj.Command)' command already exists ($($existing.CommandType)); the installed function will shadow it in new sessions."
    }
    $content = Read-ProfileContent -Path $Path
    $content = Remove-ManagedBlock -Content $content -Command $ToolObj.Command
    $block = Get-ManagedBlock -ToolObj $ToolObj
    $new = if ([string]::IsNullOrWhiteSpace($content)) { $block } else { "$content`n`n$block" }
    Write-ProfileContent -Path $Path -Content $new
    Write-Ok "Installed '$($ToolObj.Name)' as command '$($ToolObj.Command)'."
}

function Uninstall-Tool {
    param([Parameter(Mandatory)][pscustomobject]$ToolObj, [Parameter(Mandatory)][string]$Path)
    $content = Read-ProfileContent -Path $Path
    if ($content -notmatch "# >>> dev-skills tool: $([regex]::Escape($ToolObj.Command)) >>>") {
        Write-Info "'$($ToolObj.Command)' is not installed in $Path; nothing to do."
        return
    }
    $content = Remove-ManagedBlock -Content $content -Command $ToolObj.Command
    Write-ProfileContent -Path $Path -Content $content
    Write-Ok "Removed command '$($ToolObj.Command)' ('$($ToolObj.Name)') from your profile."
}

function Show-Menu {
    param([Parameter(Mandatory)][object[]]$Tools)
    $verb = if ($Uninstall) { 'Uninstall' } else { 'Install' }
    Write-Info ""
    Write-Info "dev-skills tools - $verb"
    Write-Info "=========================="
    for ($i = 0; $i -lt $Tools.Count; $i++) {
        $t = $Tools[$i]
        $ver = if ($t.Version) { " v$($t.Version)" } else { '' }
        Write-Info ("  [{0}] {1}{2}  (command: {3})" -f ($i + 1), $t.Name, $ver, $t.Command)
        if ($t.Summary) { Write-Info ("      {0}" -f $t.Summary) }
    }
    Write-Info ""
    $prompt = "Select tool number(s) to $($verb.ToLower()) (comma-separated), 'a' for all, or 'q' to quit"
    $answer = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^\s*q') { return @() }
    if ($answer -match '^\s*a') { return $Tools }
    $indices = @()
    foreach ($part in ($answer -split ',')) {
        $n = 0
        if ([int]::TryParse($part.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Tools.Count) {
            if ($indices -notcontains $n) { $indices += $n }
        }
        else { Write-Warn2 "Ignoring invalid selection '$($part.Trim())'." }
    }
    $indices | ForEach-Object { $Tools[$_ - 1] }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$allTools = @(Get-Tools)
if ($allTools.Count -eq 0) { Fail "No tools found under $ToolsRoot (each tool needs a tool.json)." }

# Resolve which tools to act on.
$targets = @()
if ($All) {
    $targets = $allTools
}
elseif (-not [string]::IsNullOrWhiteSpace($Tool)) {
    $targets = @($allTools | Where-Object { $_.Name -eq $Tool -or $_.Command -eq $Tool })
    if ($targets.Count -eq 0) {
        # When uninstalling, allow removing an orphaned block by command name even
        # if the tool no longer exists on disk.
        if ($Uninstall -and $Tool -match '^[A-Za-z][A-Za-z0-9_.-]*$') {
            $targets = @([pscustomobject]@{ Name = $Tool; Command = $Tool; Summary = ''; Version = ''; ScriptPath = '' })
        }
        else {
            Fail "No tool named or commanded '$Tool'. Available: $(( $allTools | ForEach-Object { $_.Name }) -join ', ')."
        }
    }
}
else {
    $targets = @(Show-Menu -Tools $allTools)
}

if ($targets.Count -eq 0) { Write-Info "Nothing selected. Exiting."; exit 0 }

$profilePath = Resolve-ProfilePath
$action = if ($Uninstall) { 'uninstall' } else { 'install' }
Write-Info ""
Write-Info "About to $action the following in: $profilePath"
$targets | ForEach-Object { Write-Info "  - $($_.Name) (command: $($_.Command))" }

if (-not $Yes) {
    $confirm = Read-Host "Proceed? [y/N]"
    if ($confirm -notmatch '^\s*y') { Write-Info "Cancelled."; exit 0 }
}

foreach ($t in $targets) {
    if ($Uninstall) { Uninstall-Tool -ToolObj $t -Path $profilePath }
    else { Install-Tool -ToolObj $t -Path $profilePath }
}

Write-Info ""
if ($Uninstall) {
    Write-Info "Restart PowerShell for the change to take effect."
    Write-Info "To drop the command from the current session too, run: Remove-Item Function:\$($targets[0].Command) -ErrorAction SilentlyContinue"
}
else {
    Write-Info "Restart PowerShell (or run: . `$PROFILE.CurrentUserAllHosts) to load the new command(s)."
    Write-Info "Then try, e.g.:  $($targets[0].Command) help"
}
