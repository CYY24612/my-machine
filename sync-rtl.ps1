# sync-rtl.ps1 - copy RTL from 01-cpu to the Gowin project (01-cpu is the only source)
#
# Why: the Gowin project cannot reference ../01-cpu/rtl cleanly, so cpu.v must be
# copied. Two copies drift: simulation passes but the board misbehaves (very hard
# to debug). Always run this after changing the CPU.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

$pairs = @(
    @{ src = '01-cpu\rtl\cpu.v';     dst = 'fpga\cpu_on_fpga\src\cpu.v' },
    @{ src = '01-cpu\rtl\uart_tx.v'; dst = 'fpga\cpu_on_fpga\src\uart_tx.v' }
)

$changed = 0
foreach ($p in $pairs) {
    $s = Join-Path $root $p.src
    $d = Join-Path $root $p.dst
    if (-not (Test-Path $s)) { Write-Host "skip (missing): $($p.src)" -ForegroundColor Yellow; continue }

    $srcText = [System.IO.File]::ReadAllText($s, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n"
    $dstText = if (Test-Path $d) { [System.IO.File]::ReadAllText($d, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n" } else { '' }

    if ($srcText -eq $dstText) {
        Write-Host "same: $($p.dst)" -ForegroundColor DarkGray
        continue
    }

    $out = $srcText -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($d, $out, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "synced: $($p.src) -> $($p.dst)" -ForegroundColor Green
    $changed++
}

if ($changed -eq 0) {
    Write-Host "`nAll in sync." -ForegroundColor Green
} else {
    Write-Host "`nSynced $changed file(s). Re-run synthesis!" -ForegroundColor Yellow
}