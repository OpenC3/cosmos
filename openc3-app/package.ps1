# Build a NATIVE Windows installer (.msi via WiX and/or .exe via NSIS) for the
# host architecture. Run this on Windows in PowerShell:
#
#   powershell -ExecutionPolicy Bypass -File .\package.ps1
#
# Output lands in dist\installers\.

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

Write-Host "Packaging OpenC3 COSMOS for Windows $env:PROCESSOR_ARCHITECTURE"

# 1. Build the optimized release binary.
Write-Host "Building release binary..."
cargo build --release

# 2. Ensure the packaging tool is available.
cargo packager --version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing cargo-packager..."
    cargo install cargo-packager --locked
}

# 3. Produce the host-native installer(s) (NSIS .exe and/or WiX .msi).
$out = "dist\installers"
New-Item -ItemType Directory -Force -Path $out | Out-Null
Write-Host "Building installer(s) into $out\ ..."
cargo packager --release --out-dir $out

Write-Host ""
Write-Host "Done. Installers in $out\:"
Get-ChildItem -Path $out -Include *.msi, *.exe -Recurse | ForEach-Object { $_.FullName }
