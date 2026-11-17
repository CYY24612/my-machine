# build.ps1 —— 一键配置 + 编译（不用记 PATH、不用记 cmake 参数）
#   用法： .\build.ps1
#   加 -Clean 可以删掉 build 目录彻底重来： .\build.ps1 -Clean
param([switch]$Clean)

$ErrorActionPreference = 'Stop'

# --- Qt 5.12.9 + 自带 MinGW 7.3.0 ---
$qt  = "E:\SoftWare\QT\Qt5.12.9\5.12.9\mingw73_64"
$mgw = "E:\SoftWare\QT\Qt5.12.9\Tools\mingw730_64\bin"
if (-not (Test-Path "$qt\bin\qmake.exe")) { throw "找不到 Qt：$qt" }
if (-not (Test-Path "$mgw\g++.exe"))      { throw "找不到 MinGW：$mgw" }

$env:PATH = "$mgw;$qt\bin;" + $env:PATH
# 让控制台正确显示 UTF-8（源码是 UTF-8，否则中文是乱码）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Push-Location $PSScriptRoot
try {
    if ($Clean -and (Test-Path build)) {
        Write-Host "删除 build\ ..." -ForegroundColor Yellow
        Remove-Item build -Recurse -Force
    }
    if (-not (Test-Path build)) {
        Write-Host "配置 ..." -ForegroundColor Cyan
        cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Debug
        if ($LASTEXITCODE -ne 0) { throw "cmake 配置失败" }
    }
    Write-Host "编译 ..." -ForegroundColor Cyan
    cmake --build build -j
    if ($LASTEXITCODE -ne 0) { throw "编译失败（看上面第一条 error）" }

    Write-Host ""
    Write-Host "完成。产物：" -ForegroundColor Green
    Get-ChildItem "$PSScriptRoot\build\*.exe" -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host ("  {0}  ({1:N0} KB)" -f $_.Name, ($_.Length / 1KB)) }
    Write-Host ""
    Write-Host "运行： .\run.ps1" -ForegroundColor Green
    Write-Host "测试： .\run.ps1 -Test" -ForegroundColor Green
}
finally {
    Pop-Location
}