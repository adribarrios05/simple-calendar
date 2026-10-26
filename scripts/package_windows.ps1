param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$packagePath = $null
Push-Location $projectRoot
try {
    $versionMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path $projectRoot 'pubspec.yaml')), '(?m)^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(\d+)\s*$')
    if (-not $versionMatch.Success) { throw 'Expected pubspec version: major.minor.patch[-prerelease]+build.' }
    $appVersion = $versionMatch.Groups[1].Value
    $buildNumber = $versionMatch.Groups[2].Value
    $expectedVersion = "$appVersion+$buildNumber"
    # Keep the project's license separate from dependencies' original terms.
    foreach ($requiredDocument in @('LICENSE.md', 'THIRD_PARTY_NOTICES.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $requiredDocument))) {
            throw "Missing distribution document: $requiredDocument"
        }
    }
    if (-not $SkipBuild) {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows Release build failed.' }
    }
    $releasePath = Join-Path $projectRoot 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath (Join-Path $releasePath 'SimpleCalendar.exe'))) { throw 'Windows Release build is missing.' }
    $binaryVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $releasePath 'SimpleCalendar.exe')).ProductVersion
    if ($binaryVersion -ne $expectedVersion) {
        throw "Binary version '$binaryVersion' differs from pubspec '$expectedVersion'. Rebuild before packaging."
    }
    # Package a fresh runtime/document allowlist, never the entire old build.
    # Stale owner-only notes or editor settings in Release must not reach users.
    $distributionPath = Join-Path $projectRoot 'dist'
    New-Item -ItemType Directory -Path $distributionPath -Force | Out-Null
    $packagePath = Join-Path $distributionPath ('.package-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $packagePath | Out-Null
    Copy-Item -LiteralPath (Join-Path $releasePath 'SimpleCalendar.exe') -Destination $packagePath
    Get-ChildItem -LiteralPath $releasePath -File -Filter '*.dll' | Copy-Item -Destination $packagePath
    Copy-Item -LiteralPath (Join-Path $releasePath 'data') -Destination $packagePath -Recurse
    # Add the app-local Visual C++ runtime for machines without Visual Studio.
    $vswherePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vsPath = & $vswherePath -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
    $runtime = Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object { $_.Name -match '^\d+\.' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $runtime) { throw 'Visual C++ redistributable runtime is missing.' }
    $runtimePath = Join-Path $runtime.FullName 'x64\Microsoft.VC143.CRT'
    if (-not (Test-Path -LiteralPath $runtimePath)) { throw "Missing runtime: $runtimePath" }
    Get-ChildItem -LiteralPath $runtimePath -Filter '*.dll' | Copy-Item -Destination $packagePath -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $packagePath 'LEEME.md') -Force
    foreach ($documentName in @('README.md', 'CONTRIBUTING.md', 'ARCHITECTURE.md', 'AGENTS.md', 'LICENSE.md', 'THIRD_PARTY_NOTICES.md')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $documentName) -Destination (Join-Path $packagePath $documentName) -Force
    }
    $translationPath = Join-Path $projectRoot 'docs\i18n'
    if (Test-Path -LiteralPath $translationPath) {
        New-Item -ItemType Directory -Path (Join-Path $packagePath 'docs') | Out-Null
        Copy-Item -LiteralPath $translationPath -Destination (Join-Path $packagePath 'docs') -Recurse
    }
    $screenshotPath = Join-Path $projectRoot 'docs\screenshots'
    if (Test-Path -LiteralPath $screenshotPath) {
        New-Item -ItemType Directory -Path (Join-Path $packagePath 'docs') -Force | Out-Null
        Copy-Item -LiteralPath $screenshotPath -Destination (Join-Path $packagePath 'docs') -Recurse
    }
    # Flutter's .Z bundle is gzip. Export the exact texts in readable form.
    $noticeBundlePath = Join-Path $packagePath 'data\flutter_assets\NOTICES.Z'
    if (-not (Test-Path -LiteralPath $noticeBundlePath)) {
        throw 'Missing Flutter notice bundle. Build Release before packaging.'
    }
    $noticeInput = [System.IO.File]::OpenRead($noticeBundlePath)
    try {
        $noticeDecoder = New-Object System.IO.Compression.GZipStream($noticeInput, [System.IO.Compression.CompressionMode]::Decompress)
        try {
            $noticeOutput = [System.IO.File]::Create((Join-Path $packagePath 'THIRD_PARTY_NOTICES.txt'))
            try {
                $noticeDecoder.CopyTo($noticeOutput)
            } finally { $noticeOutput.Dispose() }
        } finally { $noticeDecoder.Dispose() }
    } finally { $noticeInput.Dispose() }
    # The Material icon font's notice is separate from Flutter's package bundle.
    $flutterSdkPath = Split-Path -Parent (Split-Path -Parent (Get-Command flutter -ErrorAction Stop).Source)
    $iconLicensePath = Join-Path $flutterSdkPath 'bin\cache\artifacts\material_fonts\materialicons_license.txt'
    if (-not (Test-Path -LiteralPath $iconLicensePath)) { throw 'Material Icons license is missing from the Flutter SDK.' }
    New-Item -ItemType Directory -Path (Join-Path $packagePath 'licenses') | Out-Null
    Copy-Item -LiteralPath $iconLicensePath -Destination (Join-Path $packagePath 'licenses\MaterialIcons.txt')
    $archiveName = "SimpleCalendar-$appVersion-windows-x64.zip"
    $archivePath = Join-Path $distributionPath $archiveName
    Compress-Archive -Path (Join-Path $packagePath '*') -DestinationPath $archivePath -Force
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$archivePath.sha256", "$archiveHash  $archiveName`n", [Text.Encoding]::ASCII)
    Write-Output "Distribution prepared: $archivePath"
    Write-Output "SHA256: $archiveHash ($archivePath.sha256)"
} finally {
    if ($packagePath -and (Test-Path -LiteralPath $packagePath)) {
        $resolvedPackagePath = [IO.Path]::GetFullPath($packagePath)
        $resolvedDistRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'dist')).TrimEnd('\') + '\'
        if (-not $resolvedPackagePath.StartsWith($resolvedDistRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove staging outside the distribution directory.'
        }
        Remove-Item -LiteralPath $resolvedPackagePath -Recurse -Force
    }
    Pop-Location
}
