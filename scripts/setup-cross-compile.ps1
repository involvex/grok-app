#!/usr/bin/env pwsh
# Install toolchains for Grok App desktop builds (macOS ARM / Intel + Windows x64).
# On macOS/Linux, Windows installers use cargo-xwin + NSIS (Tauri official path).
# Run once on each developer machine (or after rustup update):
#   bun run setup:cross
#   .\scripts\setup-cross-compile.ps1

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
Set-Location $Root

$IsWindows = $PSVersionTable.Platform -eq "Win32NT" -or $env:OS -eq "Windows_NT"
$OSDesc = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
$IsMacOS = $OSDesc -match "Darwin" -or (uname -s 2>$null) -eq "Darwin"
$IsLinux = $OSDesc -match "Linux" -or (uname -s 2>$null) -eq "Linux"

if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    Write-Error "error: rustup not found. Install from https://rustup.rs"
    exit 1
}

Write-Host "==> Ensuring stable toolchain"
rustup toolchain install stable
rustup default stable

$HostTriple = (rustc -vV) | Select-String "host:" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
Write-Host "Host triple: $HostTriple"

$Targets = @(
    "aarch64-apple-darwin",   # macOS Apple Silicon
    "x86_64-apple-darwin",    # macOS Intel
    "x86_64-pc-windows-msvc" # Windows x64
)

foreach ($t in $Targets) {
    Write-Host "==> rustup target add $t"
    try {
        rustup target add $t
    } catch {
        Write-Warning "warn: failed to add $t (ok if unsupported on this host)"
    }
}

if ($IsMacOS) {
    Write-Host "==> macOS: Xcode CLT check"
    try {
        xcode-select -p | Out-Null
    } catch {
        Write-Warning "warn: Xcode Command Line Tools missing — run: xcode-select --install"
    }

    # Homebrew LLVM provides clang-cl
    if (Test-Path "/opt/homebrew/opt/llvm/bin") {
        $env:PATH = "/opt/homebrew/opt/llvm/bin:$env:PATH"
        Write-Host "==> Found Homebrew LLVM: /opt/homebrew/opt/llvm"
    }
    elseif (Test-Path "/usr/local/opt/llvm/bin") {
        $env:PATH = "/usr/local/opt/llvm/bin:$env:PATH"
        Write-Host "==> Found Homebrew LLVM: /usr/local/opt/llvm"
    }
    else {
        Write-Warning "warn: brew llvm not found. For Windows cross-builds: brew install llvm"
    }

    if (Get-Command makensis -ErrorAction SilentlyContinue) {
        Write-Host "==> Found makensis: $(Get-Command makensis | Select-Object -ExpandProperty Source)"
    } else {
        Write-Warning "warn: makensis not found. For Windows NSIS installer: brew install makensis"
    }

    if (Get-Command cargo-xwin -ErrorAction SilentlyContinue) {
        Write-Host "==> Found cargo-xwin: $(Get-Command cargo-xwin | Select-Object -ExpandProperty Source)"
    } else {
        Write-Host "==> Installing cargo-xwin (Windows MSVC cross linker wrapper)"
        cargo install --locked cargo-xwin
    }

    Write-Host "==> Ensuring Windows SDK cache (cargo-xwin / xwin)…"
    try {
        cargo xwin check --manifest-path src-tauri/Cargo.toml --target x86_64-pc-windows-msvc -q 2>$null
        Write-Host "    cargo-xwin check OK"
    } catch {
        Write-Host "    (optional) first Windows build will download CRT/SDK into cargo-xwin cache"
    }
}

if ($IsLinux) {
    Write-Host "==> Linux host: for Windows cross-builds install nsis, llvm, and cargo-xwin"
    Write-Host "    See https://v2.tauri.app/distribute/windows-installer/#build-windows-apps-on-linux-and-macos"
    if (-not (Get-Command cargo-xwin -ErrorAction SilentlyContinue)) {
        Write-Host "==> Installing cargo-xwin"
        try { cargo install --locked cargo-xwin } catch {}
    }
}

if ($IsWindows) {
    Write-Host "==> Windows host detected"
    Write-Host "    Ensure WebView2 + Visual Studio Build Tools (C++/MSVC) are installed."
}

Write-Host ""
Write-Host "Done. Useful commands:"
Write-Host "  bun run build:mac-arm      # aarch64-apple-darwin"
Write-Host "  bun run build:mac-intel   # x86_64-apple-darwin"
Write-Host "  bun run build:win         # x86_64-pc-windows-msvc (macOS/Linux via cargo-xwin; native on Windows)"
Write-Host "  bun run build:mac-all     # both mac targets"
Write-Host "  .\scripts\build-local.ps1 all   # mac-arm + mac-intel + win (macOS)"
Write-Host "  bun run build             # host default"
Write-Host ""
Write-Host "Windows cross-build (macOS/Linux) uses:"
Write-Host "  tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc"
Write-Host "Artifacts: src-tauri/target/<triple>/release/bundle/"
