<#
    Sync 01-cpu to the Kylin VM and run the simulation there.

    Windows is the single source of truth.

    Three Windows-specific pitfalls are handled here:
      1. "tar | ssh" corrupts the gzip stream (PowerShell 5.1 pipes native
         output as text) -> we pack to a file and scp it instead.
      2. calling ssh directly hangs waiting for stdin EOF -> Start-Process
         with RedirectStandardInput.
      3. Start-Process -PassThru may leave ExitCode empty -> the remote
         command echoes __RC__=$? and we parse that instead.
#>
param(
    [string]$Remote = 'kylin',
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$cpuDir = $PSScriptRoot
$root   = Split-Path $cpuDir -Parent
$leaf   = Split-Path $cpuDir -Leaf
if ([string]::IsNullOrWhiteSpace($leaf)) { throw 'cannot determine folder name' }

function Invoke-Remote {
    param([string]$Cmd)

    # 让远端显式回报退出码（不依赖 Start-Process 的 ExitCode）
    $wrapped = $Cmd + '; __rc=$?; echo "__RC__=$__rc"'

    $empty = New-TemporaryFile
    $out = Join-Path $env:TEMP ('rout-' + [guid]::NewGuid().ToString('N') + '.txt')
    $err = Join-Path $env:TEMP ('rerr-' + [guid]::NewGuid().ToString('N') + '.txt')

    $p = Start-Process -FilePath 'ssh' `
        -ArgumentList '-o', 'BatchMode=yes', $Remote, $wrapped `
        -NoNewWindow -PassThru `
        -RedirectStandardInput  $empty `
        -RedirectStandardOutput $out `
        -RedirectStandardError  $err
    $finished = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) { try { $p.Kill() } catch {}; throw "remote timed out: $Cmd" }

    $lines  = if (Test-Path $out) { @(Get-Content $out -Encoding UTF8) } else { @() }
    $stderr = if (Test-Path $err) { @(Get-Content $err -Encoding UTF8) } else { @() }
    Remove-Item $empty -Force -ErrorAction SilentlyContinue

    $rc = $null
    $body = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($l -match '^__RC__=(-?\d+)\s*$') { $rc = [int]$Matches[1] }
        else { $body.Add($l) }
    }
    if ($null -eq $rc) { throw "no exit code from remote (command: $Cmd)" }

    return [pscustomobject]@{ Exit = $rc; Out = $body.ToArray(); Err = $stderr }
}

# ---------------------------------------------------------------- 1. pack
Write-Host "[1/4] pack $leaf ..." -ForegroundColor Cyan
$tgz = Join-Path $env:TEMP "$leaf.tgz"
if (Test-Path $tgz) { Remove-Item $tgz -Force }
tar -czf $tgz -C $root $leaf
if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
Write-Host ('      {0:N0} KB' -f ((Get-Item $tgz).Length / 1KB))

# ---------------------------------------------------------------- 2. upload
Write-Host "[2/4] upload -> ${Remote}:/tmp/ ..." -ForegroundColor Cyan
scp -o BatchMode=yes -q $tgz "${Remote}:/tmp/$leaf.tgz"
if ($LASTEXITCODE -ne 0) { throw "scp failed: check 'ssh $Remote'" }

# ---------------------------------------------------------------- 3. extract
Write-Host "[3/4] extract on remote ..." -ForegroundColor Cyan
$r = Invoke-Remote "mkdir -p ~/work; rm -rf ~/work/$leaf; tar -xzf /tmp/$leaf.tgz -C ~/work; rm -f /tmp/$leaf.tgz"
if ($r.Exit -ne 0) {
    $r.Out | ForEach-Object { Write-Host $_ }
    $r.Err | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    throw "extract failed (exit $($r.Exit))"
}

# ---------------------------------------------------------------- 4. run
Write-Host "[4/4] run run.sh on $Remote" -ForegroundColor Cyan
$r = Invoke-Remote "cd ~/work/$leaf && bash run.sh"
$r.Out | ForEach-Object { Write-Host $_ }
if ($r.Err.Count -gt 0) {
    Write-Host '--- stderr ---' -ForegroundColor DarkGray
    $r.Err | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
}
Remove-Item $tgz -Force -ErrorAction SilentlyContinue

if ($r.Exit -ne 0) {
    Write-Host "FAILED (exit $($r.Exit))" -ForegroundColor Red
    exit 1
}
Write-Host 'done' -ForegroundColor Green