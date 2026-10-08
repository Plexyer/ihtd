$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    cargo test --workspace --locked
    if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed' }
    Set-Location (Join-Path $projectRoot 'app')
    flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    flutter analyze lib test integration_test
    if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed' }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    Write-Output 'Ready: app/build/windows/x64/runner/Release/ihtd.exe'
} finally {
    Pop-Location
}
