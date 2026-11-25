<#
  fix-encoding.ps1 - rewrite a text file as UTF-8 (with or without BOM).

  Why this exists:
    A UTF-8 file WITHOUT a BOM is a guessing game for Windows editors.
    Notepad / some VS Code settings assume ANSI (GBK) and render Chinese as
    garbage ("mojibake"). Browsers do not care (they honour <meta charset>),
    but editors do. Adding a BOM makes every Windows tool detect UTF-8.

  Usage:
    .\fix-encoding.ps1 -Path .\some.html                 # auto: html -> BOM
    .\fix-encoding.ps1 -Path .\note.md                   # auto: md   -> no BOM
    .\fix-encoding.ps1 -Path .\x.txt -Mode bom           # force BOM
    .\fix-encoding.ps1 -Path .\x.txt -OutPath .\y.txt    # write elsewhere

  Mode "auto" decides by extension:
    BOM    : .html .htm .css .js .ps1 .xml .svg
    no BOM : .md .txt .v .sv .c .h .cpp .py .sh .json .cst .sdc
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet('auto', 'bom', 'nobom')][string]$Mode = 'auto',
    [string]$OutPath,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'

$src = (Resolve-Path $Path).Path
$bytes = [System.IO.File]::ReadAllBytes($src)

# ---- 1. detect BOM ----
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

# ---- 2. decode: prefer strict UTF-8, fall back to GB18030 ----
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$text = $null
$decodedAs = ''

try {
    $text = $strictUtf8.GetString($bytes)
    $decodedAs = 'utf-8'
} catch {
    try {
        $gb = [System.Text.Encoding]::GetEncoding(54936)   # GB18030
        $text = $gb.GetString($bytes)
        $decodedAs = 'gb18030'
    } catch {
        throw "Cannot decode $src as UTF-8 or GB18030. Refusing to touch it."
    }
}

# strip a leading U+FEFF that the decode may have produced
if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

# ---- 3. decide target BOM ----
$ext = [System.IO.Path]::GetExtension($src).ToLowerInvariant()
$bomList = @('.html', '.htm', '.css', '.js', '.ps1', '.xml', '.svg')
switch ($Mode) {
    'bom'   { $wantBom = $true }
    'nobom' { $wantBom = $false }
    default { $wantBom = ($bomList -contains $ext) }
}

# ---- 4. write ----
$dst = if ($OutPath) { $OutPath } else { $src }
if (-not $OutPath -and -not $NoBackup) {
    Copy-Item -LiteralPath $src -Destination ($src + '.bak') -Force
}

$target = New-Object System.Text.UTF8Encoding($wantBom)
[System.IO.File]::WriteAllText($dst, $text, $target)

# ---- 5. report ----
$outBytes = [System.IO.File]::ReadAllBytes($dst)
$outHasBom = ($outBytes.Length -ge 3 -and $outBytes[0] -eq 0xEF -and $outBytes[1] -eq 0xBB -and $outBytes[2] -eq 0xBF)
$cjk = ([regex]::Matches($text, '[\u4e00-\u9fff]')).Count

Write-Host ("source     : {0}" -f $src)
Write-Host ("decoded as : {0}" -f $decodedAs)
Write-Host ("had BOM    : {0}" -f $hasBom)
Write-Host ("target BOM : {0}  (mode={1})" -f $wantBom, $Mode)
Write-Host ("output     : {0}  ({1} bytes, BOM={2})" -f $dst, $outBytes.Length, $outHasBom)
Write-Host ("CJK chars  : {0}" -f $cjk)
if ($cjk -eq 0 -and $text -match '[\u00c0-\u00ff]{3,}') {
    Write-Host "WARNING: looks like mojibake (lots of Latin-1 accents). Source may be double-encoded." -ForegroundColor Yellow
}
Write-Host "done." -ForegroundColor Green