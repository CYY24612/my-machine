# run.ps1 —— 运行程序（自动把 Qt 的 DLL 目录加进 PATH）
#   用法： .\run.ps1          跑界面
#          .\run.ps1 -Test    跑协议单测
param([switch]$Test)

$ErrorActionPreference = 'Stop'

$qt = "E:\SoftWare\QT\Qt5.12.9\5.12.9\mingw73_64"
$env:PATH = "$qt\bin;" + $env:PATH
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$exe = if ($Test) { "$PSScriptRoot\build\test_protocol.exe" }
       else       { "$PSScriptRoot\build\car_pc.exe" }

if (-not (Test-Path $exe)) {
    Write-Host "找不到 $exe" -ForegroundColor Red
    Write-Host "先编译： .\build.ps1" -ForegroundColor Yellow
    exit 1
}

if ($Test) {
    & $exe
    exit $LASTEXITCODE
} else {
    # GUI 程序用 Start-Process 启动，不占住这个终端
    Start-Process -FilePath $exe -WorkingDirectory $PSScriptRoot
    Write-Host "已启动 car_pc.exe" -ForegroundColor Green
}