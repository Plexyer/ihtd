# Use only on a Windows build machine. No signing credentials are involved.
$ErrorActionPreference = 'Stop'
$version = '6.4.3'
$sha256 = 'f3c42116542c4cc57263c5ba6c4feabfc49fe771f2f98a79d2f7628b8762723b'
$installer = Join-Path ([IO.Path]::GetTempPath()) "ihtd-innosetup-$version.exe"
$destination = Join-Path $env:LOCALAPPDATA "IHTD-BuildTools\InnoSetup-$version"
Invoke-WebRequest -Uri "https://github.com/jrsoftware/issrc/releases/download/is-6_4_3/innosetup-$version.exe" -OutFile $installer
if ((Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256) {
    throw 'Inno Setup download checksum mismatch'
}
if ((Get-AuthenticodeSignature $installer).Status -ne 'Valid') {
    throw 'Inno Setup download has no valid publisher signature'
}
$process = Start-Process $installer -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', "/DIR=`"$destination`"") -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Inno Setup installation failed: $($process.ExitCode)" }
$compiler = Join-Path $destination 'ISCC.exe'
if (-not (Test-Path $compiler)) { throw 'Inno Setup compiler missing after installation' }
if ($env:GITHUB_ENV) { Add-Content $env:GITHUB_ENV "IHTD_ISCC=$compiler" }
Write-Output "Inno Setup compiler: $compiler"
