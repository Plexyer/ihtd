param([string] $CompilerPath = $env:IHTD_ISCC)

$ErrorActionPreference = 'Stop'
# Installs and uninstalls IHTD, writes HKCU registrations, and launches the app.
# Keep this destructive test out of everyday workstations.
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run installer verification only on a disposable GitHub Actions Windows runner' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$metadataJson = & python (Join-Path $PSScriptRoot 'release-version.py')
if ($LASTEXITCODE -ne 0) { throw 'Version validation failed' }
$version = ($metadataJson | ConvertFrom-Json).version
$packages = Join-Path $projectRoot 'dist/windows'
$stage = Join-Path $packages "IHTD-$version"
$setup = Join-Path $packages "IHTD-$version-windows-x64-setup.exe"
$work = Join-Path $env:RUNNER_TEMP "ihtd-installer-test-$([guid]::NewGuid())"
$install = Join-Path $work 'Installed IHTD'
$registry = 'HKCU:\Software\Classes\IHTD.Collection'
$openWith = 'HKCU:\Software\Classes\.ihtd\OpenWithProgids'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E216F57E-504E-43AB-8536-FC8509C1A40D}_is1'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'IHTD.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'IHTD.lnk'
foreach ($existing in @($registry, $uninstallKey, $startMenu, $desktop)) {
    if (Test-Path $existing) { throw "IHTD is already installed or registered on this runner: $existing" }
}
if (-not $env:IHTD_INSTALLER_TEST_COLLECTION -or -not (Test-Path $env:IHTD_INSTALLER_TEST_COLLECTION)) {
    throw 'UI integration test must produce a real installer preservation fixture'
}
New-Item -ItemType Directory -Path $work | Out-Null
$fixture = Join-Path $work '日本 travel collection.ihtd'
Copy-Item $env:IHTD_INSTALLER_TEST_COLLECTION $fixture
$fixtureHash = (Get-FileHash $fixture -Algorithm SHA256).Hash

function Invoke-Setup([string] $Executable, [string[]] $Options) {
    $process = Start-Process $Executable -ArgumentList $Options -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Setup failed ($($process.ExitCode)): $Executable" }
}
function Assert-FileHash([string] $Path, [string] $Expected) {
    if (-not (Test-Path $Path) -or (Get-FileHash $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw "Data was removed or changed: $Path"
    }
}
function Assert-Installed([string] $ExpectedVersion) {
    if ((Get-ItemProperty $uninstallKey).DisplayVersion -ne $ExpectedVersion) { throw 'Installer version registration is incorrect' }
    if ((Get-ItemProperty $uninstallKey).InstallLocation.TrimEnd('\') -ne $install) { throw 'Installer did not reuse its installation directory' }
    foreach ($file in Get-ChildItem $stage -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($stage, $file.FullName)
        Assert-FileHash (Join-Path $install $relative) (Get-FileHash $file.FullName -Algorithm SHA256).Hash
    }
    foreach ($link in @($startMenu, $desktop)) {
        if (-not (Test-Path $link)) { throw "Shortcut missing: $link" }
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
        if ($shortcut.TargetPath -ne (Join-Path $install 'ihtd.exe')) { throw 'Shortcut targets the wrong executable' }
    }
    if ((Get-Item $openWith).GetValueNames() -notcontains 'IHTD.Collection') { throw 'Open-with registration missing' }
    $command = (Get-Item "$registry\shell\open\command").GetValue('')
    if ($command -ne "`"$(Join-Path $install 'ihtd.exe')`" `"%1`"") { throw 'Document open command must quote both executable and document' }
}
function Assert-Launch([string] $Executable, [string[]] $Options = @()) {
    # Launch from a different directory, as Explorer does for a document.
    $launch = @{ FilePath = $Executable; WorkingDirectory = $work; PassThru = $true }
    if ($Options.Count -gt 0) { $launch.ArgumentList = $Options }
    $process = Start-Process @launch
    try {
        Start-Sleep -Seconds 10
        $process.Refresh()
        if ($process.HasExited -or $process.MainWindowHandle -eq 0) { throw 'Installed release failed to show its window' }
        if (-not $process.CloseMainWindow()) { throw 'Installed release refused a normal close' }
        if (-not $process.WaitForExit(15000)) { throw 'Installed release did not exit after close' }
    } finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}

# Check that the portable ZIP has the same complete payload, including the CRT.
$expanded = Join-Path $work 'Portable'
Expand-Archive (Join-Path $packages "IHTD-$version-windows-x64.zip") $expanded
$portable = Join-Path $expanded "IHTD-$version"
foreach ($file in Get-ChildItem $stage -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($stage, $file.FullName)
    Assert-FileHash (Join-Path $portable $relative) (Get-FileHash $file.FullName -Algorithm SHA256).Hash
}
Assert-Launch (Join-Path $portable 'ihtd.exe')

# Use the real payload with an older installer version to test upgrade identity.
# This tests installer migration; it is not a claim to run historical app code.
& $CompilerPath '/DAppVersion=0.0.0' '/DAppBuild=1' "/DBundleDir=$stage" "/DOutputDir=$work" (Join-Path $projectRoot 'packaging/windows/ihtd.iss')
if ($LASTEXITCODE -ne 0) { throw 'Baseline installer compilation failed' }
Invoke-Setup (Join-Path $work 'IHTD-0.0.0-windows-x64-setup.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$install`"", '/TASKS=desktopicon,fileassociation', "/LOG=`"$work\install.log`"")
Assert-Installed '0.0.0'

# Real collection and support/recovery files must survive upgrade and removal.
# The support directory is derived from existing CompanyName/ProductName and
# intentionally keeps those stable across the portable/installer transition.
$support = Join-Path $env:APPDATA 'dev.ihtd/IHTD'
New-Item -ItemType Directory -Path (Join-Path $support 'recovery') -Force | Out-Null
$recovery = Join-Path $support "recovery/installer-test-$([guid]::NewGuid()).ihtd"
Copy-Item $fixture $recovery
$userFile = Join-Path $install 'User collection.ihtd'
Copy-Item $fixture $userFile
Assert-Launch (Join-Path $install 'ihtd.exe') @("`"$fixture`"")

# Omit DIR and TASKS: upgrading must retain the user's earlier choices.
Invoke-Setup $setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$work\upgrade.log`"")
Assert-Installed $version
Assert-FileHash $fixture $fixtureHash
Assert-FileHash $userFile $fixtureHash
Assert-FileHash $recovery $fixtureHash
Assert-Launch (Join-Path $install 'ihtd.exe') @("`"$fixture`"")

Invoke-Setup (Join-Path $install 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$work\uninstall.log`"")
foreach ($removed in @((Join-Path $install 'ihtd.exe'), $registry, $uninstallKey, $startMenu, $desktop)) {
    if (Test-Path $removed) { throw "Uninstall left application integration behind: $removed" }
}
if ((Test-Path $openWith) -and (Get-Item $openWith).GetValueNames() -contains 'IHTD.Collection') { throw 'Uninstall left the Open-with registration behind' }
Assert-FileHash $fixture $fixtureHash
Assert-FileHash $userFile $fixtureHash
Assert-FileHash $recovery $fixtureHash

# A clean reinstall can omit the optional shortcuts/association entirely.
Invoke-Setup $setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$install`"", '/TASKS=', "/LOG=`"$work\reinstall.log`"")
if (-not (Test-Path $startMenu)) { throw 'Start Menu shortcut missing after reinstall' }
if ((Test-Path $desktop) -or (Test-Path $registry)) { throw 'Unselected installer tasks were applied' }
Assert-Launch (Join-Path $install 'ihtd.exe')
Invoke-Setup (Join-Path $install 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
Assert-FileHash $fixture $fixtureHash
Assert-FileHash $userFile $fixtureHash
Assert-FileHash $recovery $fixtureHash
Write-Output "Installer verification passed: install, upgrade, shortcuts, file registration, launches, uninstall, reinstall and preserved data. Logs: $work"
