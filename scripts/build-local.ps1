#!/usr/bin/env pwsh
# Local release-style builds for supported desktop targets.

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
Set-Location $Root

$TargetAlias = if ($args.Count -gt 0) { $args[0] } else { "host" }

function Need-Cmd {
    param([string]$Cmd)
    if (-not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
        Write-Error "error: missing command: $Cmd"
        exit 1
    }
}

function Prepend-Homebrew-LLVM {
    if (Test-Path "/opt/homebrew/opt/llvm/bin") {
        $env:PATH = "/opt/homebrew/opt/llvm/bin:$env:PATH"
    }
    elseif (Test-Path "/usr/local/opt/llvm/bin") {
        $env:PATH = "/usr/local/opt/llvm/bin:$env:PATH"
    }
}

Need-Cmd "bun"
Need-Cmd "rustc"
Need-Cmd "cargo"

$IsWinEnv = ($env:OS -eq "Windows_NT") -or ($PSVersionTable.Platform -eq "Win32NT")
$IsMacEnv = $false
$IsLinEnv = $false

if (-not $IsWinEnv) {
    if (Get-Command uname -ErrorAction SilentlyContinue) {
        $unameS = uname -s
        if ($unameS -eq "Darwin") { $IsMacEnv = $true }
        if ($unameS -eq "Linux") { $IsLinEnv = $true }
    }
}

if ($IsMacEnv) {
    if (Get-Command uname -ErrorAction SilentlyContinue) {
        $Arch = uname -m
    } else {
        $Arch = "arm64"
    }
} elseif ($IsWinEnv) {
    $Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
} else {
    if (Get-Command uname -ErrorAction SilentlyContinue) {
        $Arch = uname -m
    } else {
        $Arch = "x86_64"
    }
}

function Get-HostMacTriple {
    if ($Arch -eq "arm64" -or $Arch -eq "aarch64" -or $Arch -eq "Arm64") {
        return "aarch64-apple-darwin"
    }
    elseif ($Arch -eq "x86_64" -or $Arch -eq "X64") {
        return "x86_64-apple-darwin"
    }
    else {
        Write-Error "error: unsupported Darwin arch: $Arch"
        exit 1
    }
}

function List-Artifacts {
    param([string]$Triple)
    Write-Host ""
    Write-Host "-------- Artifacts ($Triple) --------"
    $Base = "src-tauri/target/$Triple/release/bundle"
    if (-not (Test-Path $Base)) {
        Write-Host "(no bundle dir yet: $Base)"
        return
    }
    $Patterns = @("*.dmg", "*.app", "*-setup.exe", "*.AppImage", "*.deb", "*.rpm", "*.msi")
    $Found = $false
    foreach ($Pattern in $Patterns) {
        $Files = Get-ChildItem -Path $Base -Recurse -Filter $Pattern -ErrorAction SilentlyContinue
        foreach ($File in $Files) {
            $Found = $true
            Write-Host $File.FullName
        }
    }
    if (-not $Found) {
        Write-Host "Bundle root: $Base"
    }
    Write-Host "Open folder: $Root/$Base"
}

function Print-Help {
    Write-Host "Grok App - local platform builds"
    Write-Host ""
    Write-Host "  bun run build                 Current host default"
    Write-Host "  bun run build:mac             This Mac only"
    Write-Host "  bun run build:mac-arm         macOS aarch64-apple-darwin"
    Write-Host "  bun run build:mac-intel       macOS x86_64-apple-darwin"
    Write-Host "  bun run build:mac-all         Both Mac targets"
    Write-Host "  bun run build:win             Windows x64 NSIS"
    Write-Host "  bun run build:linux           Linux x64"
    Write-Host "  bun run build:all             mac-arm + mac-intel + win"
    Write-Host ""
    Write-Host "First-time deps: bun install && bun run setup:cross"
}

function Build-Target {
    param([string]$Triple)
    Write-Host ""
    Write-Host "======== Building target: $Triple ========"
    try { rustup target add $Triple 2>$null } catch {}
    bunx tauri build --target $Triple
    List-Artifacts $Triple
}

function Build-Windows {
    $Triple = "x86_64-pc-windows-msvc"
    Write-Host ""
    Write-Host "======== Building target: $Triple ========"
    try { rustup target add $Triple 2>$null } catch {}

    if ($IsMacEnv -or $IsLinEnv) {
        Prepend-Homebrew-LLVM
        Need-Cmd "cargo-xwin"
        if (-not (Get-Command makensis -ErrorAction SilentlyContinue)) {
            Write-Error "error: makensis not found. On macOS: brew install makensis"
            exit 1
        }
        if (-not (Get-Command clang-cl -ErrorAction SilentlyContinue)) {
            Write-Warning "warn: clang-cl not found, may need brew llvm"
        }
        Write-Host "Using runner: cargo-xwin"
        bunx tauri build --runner cargo-xwin --target $Triple
    } else {
        Write-Host "Using native Windows MSVC toolchain"
        bunx tauri build --target $Triple
    }

    List-Artifacts $Triple
}

switch ($TargetAlias) {
    { $_ -eq "help" -or $_ -eq "-h" -or $_ -eq "--help" } {
        Print-Help
        exit 0
    }
    { $_ -eq "host" -or $_ -eq "" } {
        if ($IsMacEnv) {
            $Triple = Get-HostMacTriple
            Write-Host "======== Building for this Mac ($Arch -> $Triple) ========"
            Build-Target $Triple
        } elseif ($IsWinEnv) {
            Write-Host "======== Building for Windows ========"
            Build-Windows
        } else {
            Write-Host "======== Building host default ========"
            bunx tauri build
        }
        break
    }
    { $_ -eq "mac" -or $_ -eq "mac-current" } {
        if (-not $IsMacEnv) {
            Write-Error "error: mac builds require macOS"
            exit 1
        }
        $Triple = Get-HostMacTriple
        Build-Target $Triple
        break
    }
    { $_ -eq "mac-arm" -or $_ -eq "mac-arm64" -or $_ -eq "aarch64-apple-darwin" } {
        if (-not $IsMacEnv) {
            Write-Error "error: mac-arm builds require macOS"
            exit 1
        }
        Build-Target "aarch64-apple-darwin"
        break
    }
    { $_ -eq "mac-intel" -or $_ -eq "mac-x64" -or $_ -eq "x86_64-apple-darwin" } {
        if (-not $IsMacEnv) {
            Write-Error "error: mac-intel builds require macOS"
            exit 1
        }
        Build-Target "x86_64-apple-darwin"
        break
    }
    { $_ -eq "win" -or $_ -eq "windows" -or $_ -eq "x86_64-pc-windows-msvc" } {
        Build-Windows
        break
    }
    { $_ -eq "linux" -or $_ -eq "x86_64-unknown-linux-gnu" } {
        if (-not $IsLinEnv) {
            Write-Error "error: linux builds require a Linux host"
            exit 1
        }
        Build-Target "x86_64-unknown-linux-gnu"
        break
    }
    "all-mac" {
        if (-not $IsMacEnv) {
            Write-Error "error: all-mac requires macOS"
            exit 1
        }
        Build-Target "aarch64-apple-darwin"
        Build-Target "x86_64-apple-darwin"
        break
    }
    "all" {
        if (-not $IsMacEnv) {
            Write-Error "error: 'all' requires macOS currently"
            exit 1
        }
        Build-Target "aarch64-apple-darwin"
        Build-Target "x86_64-apple-darwin"
        Build-Windows
        break
    }
    default {
        Print-Help
        Write-Error "error: unknown target: $TargetAlias"
        exit 1
    }
}
