param([string] $CompilerPath = $env:IHTD_ISCC)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$metadataJson = & python (Join-Path $PSScriptRoot 'release-version.py')
if ($LASTEXITCODE -ne 0) { throw 'Version validation failed' }
$metadata = $metadataJson | ConvertFrom-Json
$version = $metadata.version
$bundle = Join-Path $projectRoot 'app/build/windows/x64/runner/Release'
foreach ($required in @('ihtd.exe', 'ihtd_bridge.dll', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets')) {
    if (-not (Test-Path (Join-Path $bundle $required))) { throw "Windows bundle missing $required; build the release first" }
}
if (-not $CompilerPath) {
    $compilerCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($compilerCommand) { $CompilerPath = $compilerCommand.Source }
    else { $CompilerPath = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe' }
}
if (-not (Test-Path $CompilerPath)) { throw 'Install Inno Setup 6 (scripts/install-inno-setup.ps1), then set IHTD_ISCC to its ISCC.exe path' }

$output = Join-Path $projectRoot 'dist/windows'
$stage = Join-Path $output "IHTD-$version"
if (Test-Path $stage) { throw "Package staging already exists: $stage" }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item (Join-Path $bundle '*') $stage -Recurse

# Ship Microsoft's redistributable CRT DLLs app-locally so a fresh user's
# installation needs neither an administrator nor a separate runtime installer.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path $vswhere)) { throw 'Visual Studio vswhere is required to locate the licensed redistributable CRT' }
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $visualStudio) { throw 'Visual Studio C++ workload not found' }
$runtimeDirectories = Get-ChildItem (Join-Path $visualStudio 'VC/Redist/MSVC') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version] $_.Name } -Descending
$runtime = $runtimeDirectories | ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $runtime) { throw 'Visual Studio x64 redistributable CRT not found' }
Copy-Item (Join-Path $runtime '*.dll') $stage
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path (Join-Path $stage $dll))) { throw "Redistributable DLL missing: $dll" }
}

$guide = Get-Content (Join-Path $projectRoot 'packaging/windows/INSTALL.md') -Raw
Set-Content (Join-Path $output 'INSTALL.md') -Value $guide.Replace('@VERSION@', $version) -Encoding utf8
$archive = Join-Path $output "IHTD-$version-windows-x64.zip"
Compress-Archive -Path $stage -DestinationPath $archive
& $CompilerPath "/DAppVersion=$version" "/DAppBuild=$($metadata.build)" "/DBundleDir=$stage" "/DOutputDir=$output" (Join-Path $projectRoot 'packaging/windows/ihtd.iss')
if ($LASTEXITCODE -ne 0) { throw 'Windows installer compilation failed' }
$setup = Join-Path $output "IHTD-$version-windows-x64-setup.exe"
if (-not (Test-Path $setup)) { throw 'Compiled setup executable missing' }
$checksums = foreach ($package in @($archive, $setup)) {
    $digest = (Get-FileHash $package -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $(Split-Path -Leaf $package)"
}
Set-Content -Path (Join-Path $output 'SHA256SUMS') -Value $checksums -Encoding ascii
Write-Output "Windows packages: $archive and $setup"
