$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionLine = Select-String -Path (Join-Path $projectRoot 'app/pubspec.yaml') -Pattern '^version: ([^+]+)'
$version = $versionLine.Matches[0].Groups[1].Value
$bundle = Join-Path $projectRoot 'app/build/windows/x64/runner/Release'
if (-not (Test-Path (Join-Path $bundle 'ihtd.exe'))) { throw 'Build the Windows release first' }
$output = Join-Path $projectRoot 'dist/windows'
$stage = Join-Path $output "IHTD-$version"
if (Test-Path $stage) { throw "Package staging already exists: $stage" }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item (Join-Path $bundle '*') $stage -Recurse
$guide = Get-Content (Join-Path $projectRoot 'packaging/windows/INSTALL.md') -Raw
Set-Content (Join-Path $output 'INSTALL.md') -Value $guide.Replace('@VERSION@', $version) -Encoding utf8
$archive = Join-Path $output "IHTD-$version-windows-x64.zip"
Compress-Archive -Path $stage -DestinationPath $archive
$digest = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path (Join-Path $output 'SHA256SUMS') -Value "$digest  $(Split-Path -Leaf $archive)" -Encoding ascii
Write-Output "Windows package: $archive"
