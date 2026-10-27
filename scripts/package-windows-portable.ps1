#!/usr/bin/env pwsh
# Build a Windows portable (绿色版) zip from a release Windows binary and upload to GitHub Release.
# Usage (CI): .\scripts\package-windows-portable.ps1 v0.1.2
# Or: $env:TAG="v0.1.2"; .\scripts\package-windows-portable.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
Set-Location $Root

$Tag = if ($args.Count -gt 0) { $args[0] } else { $env:TAG }
if (-not $Tag) {
    $Pkg = Get-Content "package.json" | ConvertFrom-Json
    $Tag = "v$($Pkg.version)"
}
$Ver = $Tag -replace '^v', ''

function Find-ReleaseExe {
    $Names = @("Grok.exe", "grok-app.exe")
    foreach ($Name in $Names) {
        $Path = "src-tauri/target/release/$Name"
        if (Test-Path $Path) {
            return $Path
        }
    }
    # Fallback
    $Found = Get-ChildItem -Path "src-tauri/target" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | 
        Where-Object { $_.FullName -match '/release/[^/]+\.exe$' -and $_.FullName -notmatch '/bundle/' } | 
        Select-Object -First 1
    if ($Found) {
        return $Found.FullName
    }
    return $null
}

$Exe = Find-ReleaseExe
if (-not $Exe -or -not (Test-Path $Exe)) {
    Write-Error "error: Windows release .exe not found under src-tauri/target/release/"
    Get-ChildItem -Path "src-tauri/target" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 40 | ForEach-Object { Write-Host $_.FullName }
    exit 1
}
Write-Host "using EXE=$Exe"

$Stage = "dist-portable/Grok_${Ver}_x64-portable"
if (Test-Path "dist-portable") {
    Remove-Item -Recurse -Force "dist-portable"
}
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item $Exe "$Stage/Grok.exe"

$ReadmeContent = @"
Grok App portable (绿色版) v$Ver
================================
1. 解压本目录到任意位置（无需安装）。
2. 双击 Grok.exe 运行。
3. 需要系统已安装 Microsoft Edge WebView2 Runtime（Win10/11 通常已自带）。
4. 真 Agent 能力仍需本机 Grok Build CLI（grok.exe）并完成登录。
5. SmartScreen 可能提示未知发布者 → 更多信息 → 仍要运行。

Extract anywhere and run Grok.exe. WebView2 required. Grok Build CLI still needed for agent sessions.
"@
Set-Content -Path "$Stage/README-portable.txt" -Value $ReadmeContent -Encoding UTF8
Write-Host "wrote $Stage/README-portable.txt"

$Out = "Grok_${Ver}_x64-portable.zip"
if (Test-Path $Out) {
    Remove-Item -Force $Out
}
Compress-Archive -Path $Stage -DestinationPath $Out -Force
Get-Item $Out | Format-Table Name, Length, LastWriteTime

if ((Get-Command gh -ErrorAction SilentlyContinue) -and ($env:GH_TOKEN -or $env:GITHUB_TOKEN)) {
    gh release upload $Tag $Out --clobber
    Write-Host "uploaded $Out to $Tag"
} else {
    Write-Host "skip upload (gh/token missing); artifact at $Out"
}
