param([switch] $ConsoleRun, [string] $ConsoleKind = 'classic')
$ErrorActionPreference = 'Stop'
$package = '@stroq/cli@0.32.0'
$terminalReport = Join-Path $env:RUNNER_TEMP "stroq-card-$ConsoleKind-289.json"
$ttyReport = Join-Path $env:RUNNER_TEMP "stroq-card-tty-$ConsoleKind-289.json"

if ($ConsoleRun) {
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $env:STROQ289_TTY_REPORT = $ttyReport
        & node -e "require('node:fs').writeFileSync(process.env.STROQ289_TTY_REPORT, JSON.stringify({tty:!!process.stdout.isTTY,columns:process.stdout.columns || 0}))"
        if ($LASTEXITCODE -ne 0) { throw 'Node could not report the console status.' }
        $tty = Get-Content -Raw $ttyReport | ConvertFrom-Json
        if (-not $tty.tty) { throw 'Node did not have a terminal.' }

        $raw = $Host.UI.RawUI
        $start = $raw.CursorPosition.Y
        & npx.cmd --yes $package --no-animation
        if ($LASTEXITCODE -ne 0) { throw 'Stroq could not draw the card.' }

        $end = $raw.CursorPosition.Y
        $region = [System.Management.Automation.Host.Rectangle]::new(0, $start, $raw.BufferSize.Width - 1, $end - 1)
        $cells = $raw.GetBufferContents($region)
        $owlCells = 0
        $lines = for ($row = 0; $row -lt $cells.GetLength(0); $row++) {
            $characters = for ($col = 0; $col -lt $cells.GetLength(1); $col++) {
                $character = $cells[$row, $col].Character
                if ($character -eq [char]0x2580 -or $character -eq [char]0x2584) { $owlCells++ }
                $character
            }
            (-join $characters).TrimEnd()
        }
        $text = $lines -join "`n"
        $result = @{
            tty = $tty.tty
            columns = $tty.columns
            powershell = $PSVersionTable.PSVersion.ToString()
            windowsTerminal = $null -ne $env:WT_SESSION
            cardTitle = $text -match 'Hoo checked 30 days'
            sessions = $text -match '2 sessions'
            owlHalfBlockCells = $owlCells
        }
        $result | ConvertTo-Json | Set-Content -LiteralPath $terminalReport -Encoding UTF8
    } catch {
        @{ error = $_.Exception.Message } | ConvertTo-Json | Set-Content -LiteralPath $terminalReport -Encoding UTF8
        exit 1
    }
    exit 0
}

$scratch = Join-Path $env:RUNNER_TEMP 'stroq-card-test'
$env:USERPROFILE = Join-Path $scratch 'home'
$env:HOME = $env:USERPROFILE
$env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $env:USERPROFILE 'AppData\Local'
$env:STROQ_HOME = Join-Path $scratch 'stroq'
$env:NPM_CONFIG_CACHE = Join-Path $scratch 'npm-cache'
$env:CLAUDE_CONFIG_DIR = Join-Path $env:USERPROFILE '.claude'
$env:CODEX_HOME = Join-Path $env:USERPROFILE '.codex'
$project = Join-Path $scratch 'Example Project'
New-Item -ItemType Directory -Path $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $project -Force | Out-Null
Set-Location -LiteralPath $project
& node (Join-Path $PSScriptRoot 'windows-card-fixture.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Could not create test sessions.' }

$os = Get-CimInstance Win32_OperatingSystem
Write-Output "$($os.Caption) $($os.Version) build $($os.BuildNumber)"
& node --version
$cardText = & npx.cmd --yes $package card --json
if ($LASTEXITCODE -ne 0) { throw 'Stroq card --json failed.' }
$card = ($cardText -join "`n") | ConvertFrom-Json
if ($card.coverage.agents.claudeCode -ne 1 -or $card.coverage.agents.codex -ne 1) {
    throw 'Stroq did not find both fixture sessions.'
}
if ($card.counts.commands -ne 1 -or $card.counts.keysSeen -ne 1 -or $card.counts.keysSent -ne 0) {
    throw 'Stroq reported unexpected counts.'
}
$seenMoment = $card.moments | Where-Object { $_.kind -eq 'key-seen' } | Select-Object -First 1
if (-not $seenMoment) { throw 'Stroq did not show the expected key-read moment.' }
$shown = (& npx.cmd --yes $package show $seenMoment.n) -join "`n"
if ($LASTEXITCODE -ne 0 -or $shown -notmatch 'STRIPE_SECRET_KEY' -or $shown -match 'FAKEwindowsCard') {
    throw 'Stroq show did not provide the expected masked evidence.'
}
Write-Output 'Session discovery, command count and masked evidence verified.'

$shellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = @('-NoProfile', '-File', ('"{0}"' -f $PSCommandPath), '-ConsoleRun')
$console = Start-Process -FilePath $shellPath -ArgumentList $arguments -PassThru
if (-not $console.WaitForExit(120000)) {
    $console.Kill()
    throw 'The separate PowerShell console did not finish.'
}
if (-not (Test-Path -LiteralPath $terminalReport)) {
    throw "The separate PowerShell console produced no report (exit $($console.ExitCode))."
}

$report = Get-Content -Raw $terminalReport
Write-Output $report
$rendered = $report | ConvertFrom-Json
if ($console.ExitCode -ne 0 -or -not $rendered.cardTitle -or -not $rendered.sessions) {
    throw 'Could not verify the card in the separate console.'
}

$terminalArchive = Join-Path $scratch 'terminal-arm64.zip'
$terminalFolder = Join-Path $scratch 'terminal-arm64'
$terminalUri = 'https://github.com/microsoft/terminal/releases/download/v1.25.3131.0/Microsoft.WindowsTerminal_1.25.3131.0_arm64.zip'
$archiveHash = 'b7e1d2a414e6368affd098d91a4cba441dcacd3ab634a6f39c8e6f5490deef89'
Invoke-WebRequest -Uri $terminalUri -OutFile $terminalArchive
if ((Get-FileHash $terminalArchive -Algorithm SHA256).Hash -ne $archiveHash) {
    throw 'Windows Terminal archive checksum differs from the published release.'
}
Expand-Archive -LiteralPath $terminalArchive -DestinationPath $terminalFolder
$terminalExe = Get-ChildItem -LiteralPath $terminalFolder -Recurse -Filter 'WindowsTerminal.exe' |
    Select-Object -First 1
if (-not $terminalExe) { throw 'The portable Windows Terminal executable is missing.' }
New-Item -Path (Join-Path $terminalExe.DirectoryName '.portable') -ItemType File -Force | Out-Null

$windowsTerminalReport = Join-Path $env:RUNNER_TEMP 'stroq-card-terminal-289.json'
$terminalArguments = @(
    '-w', 'new', '--size', '100,48', 'new-tab', '--inheritEnvironment',
    '-d', ('"{0}"' -f $project), ('"{0}"' -f $shellPath)
) + $arguments + @('-ConsoleKind', 'terminal')
$terminal = Start-Process -FilePath $terminalExe.FullName -ArgumentList $terminalArguments -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(90)
while (-not (Test-Path -LiteralPath $windowsTerminalReport) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 350
}
if (-not (Test-Path -LiteralPath $windowsTerminalReport)) {
    throw 'Windows Terminal did not produce a console report.'
}
$report = Get-Content -Raw $windowsTerminalReport
Write-Output $report
$rendered = $report | ConvertFrom-Json
if (-not $rendered.windowsTerminal -or -not $rendered.cardTitle -or -not $rendered.sessions -or $rendered.owlHalfBlockCells -eq 0) {
    throw 'Could not verify the card and owl in Windows Terminal.'
}
