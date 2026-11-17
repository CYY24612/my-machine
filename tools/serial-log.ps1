# serial-log.ps1 -- serial port logger
#   usage:
#     .\serial-log.ps1                       list COM ports
#     .\serial-log.ps1 -Port COM3            open at 115200, text mode
#     .\serial-log.ps1 -Port COM3 -Baud 9600
#     .\serial-log.ps1 -Port COM3 -Hex       hex mode (for STM32 frames)
#     .\serial-log.ps1 -Port COM3 -Log out.txt
#   exit: Ctrl + C

param(
    [string]$Port = "",
    [int]$Baud = 115200,
    [switch]$Hex,
    [string]$Log = ""
)

$ErrorActionPreference = 'Stop'

# ---- list ports if none given ----
if ([string]::IsNullOrWhiteSpace($Port)) {
    Write-Host "可用串口：" -ForegroundColor Cyan
    $all = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
    if (-not $all) {
        Write-Host "  (一个都没有 -- 设备没插，或驱动没装)" -ForegroundColor Yellow
    } else {
        $all | ForEach-Object { Write-Host ("  " + $_) }
    }
    Write-Host ""
    Write-Host "用法: .\serial-log.ps1 -Port COM3" -ForegroundColor Gray
    exit 0
}

# ---- log file ----
if ([string]::IsNullOrWhiteSpace($Log)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Log = Join-Path (Get-Location) ("serial-" + $stamp + ".log")
}
$Log = [System.IO.Path]::GetFullPath($Log)

Write-Host ("端口   : " + $Port) -ForegroundColor Green
Write-Host ("波特率 : " + $Baud) -ForegroundColor Green
if ($Hex) { Write-Host "模式   : 十六进制" -ForegroundColor Green }
else      { Write-Host "模式   : 文本" -ForegroundColor Green }
Write-Host ("日志   : " + $Log) -ForegroundColor Green
Write-Host "Ctrl+C 退出" -ForegroundColor DarkGray
Write-Host "----------------------------------------"

$sp = New-Object System.IO.Ports.SerialPort
$sp.PortName    = $Port
$sp.BaudRate    = $Baud
$sp.Parity      = [System.IO.Ports.Parity]::None
$sp.DataBits    = 8
$sp.StopBits    = [System.IO.Ports.StopBits]::One
$sp.Handshake   = [System.IO.Ports.Handshake]::None
$sp.ReadTimeout = 200
$sp.DtrEnable   = $false
$sp.RtsEnable   = $false

try {
    $sp.Open()
} catch {
    Write-Host ""
    Write-Host ("打开 " + $Port + " 失败: " + $_.Exception.Message) -ForegroundColor Red
    Write-Host ""
    Write-Host "常见原因:" -ForegroundColor Yellow
    Write-Host "  1. 该 COM 口被别的程序占用 (串口助手没关 / 另一个 PowerShell 窗口)"
    Write-Host "  2. 端口号写错了"
    Write-Host "  3. 设备已经拔掉了"
    exit 1
}

$enc = New-Object System.Text.UTF8Encoding($false)
$sw  = New-Object System.IO.StreamWriter($Log, $false, $enc)
$sw.AutoFlush = $true
$needNl = $false

try {
    while ($true) {
        try {
            $n = $sp.BytesToRead
            if ($n -le 0) { Start-Sleep -Milliseconds 30; continue }

            $buf  = New-Object byte[] $n
            $read = $sp.Read($buf, 0, $n)
            if ($read -le 0) { continue }

            if ($Hex) {
                $line = ($buf[0..($read-1)] | ForEach-Object { $_.ToString('X2') }) -join ' '
                Write-Host $line
                $sw.WriteLine($line)
            } else {
                $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
                Write-Host -NoNewline $text
                $sw.Write($text)
                $needNl = -not $text.EndsWith("`n")
            }
        } catch [System.TimeoutException] {
            # timeout is normal
        }
    }
}
finally {
    if ($needNl) { Write-Host "" }
    try { $sp.Close() } catch {}
    try { $sw.Close() } catch {}
    Write-Host ""
    Write-Host ("日志已保存: " + $Log) -ForegroundColor Cyan
}