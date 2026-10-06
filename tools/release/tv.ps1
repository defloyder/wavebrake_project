param(
    [string]$Flutter = 'C:\src\flutter\bin\flutter.bat',
    [int]$BuildNumber = 1
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mobileRoot = Join-Path $projectRoot 'wavebreak-mobile'
$tvOutput = Join-Path $projectRoot '.artifacts\tv'
function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed ($LASTEXITCODE)" }
}
Push-Location $projectRoot
try {
    $branch = & git branch --show-current
    if ($LASTEXITCODE -ne 0 -or $branch -ne 'app-main-sync') { throw 'Use app-main-sync' }
    $localHead = & git rev-parse HEAD
    $remoteHead = & git rev-parse origin/app-main-sync
    if ($LASTEXITCODE -ne 0 -or $localHead -ne $remoteHead) {
        throw 'Synchronize app-main-sync before building TV'
    }
    if ($BuildNumber -lt 1) { throw 'BuildNumber must be positive' }
    if (!(Test-Path -LiteralPath $Flutter)) { throw "Flutter not found: $Flutter" }
    foreach ($required in @('android\key.properties', 'android\app\wavebreak-release.jks',
                            'android\app\libs\hysteria_bridge.aar')) {
        if (!(Test-Path -LiteralPath (Join-Path $mobileRoot $required))) {
            throw "Missing $required; see docs/BUILD-MACHINE-SETUP.md"
        }
    }
    $sdkLine = Get-Content (Join-Path $mobileRoot 'android\local.properties') |
        Where-Object { $_ -like 'sdk.dir=*' } | Select-Object -First 1
    if (!$sdkLine) { throw 'sdk.dir missing from android/local.properties' }
    $sdkPath = $sdkLine.Substring(8).Replace('\\', '\').Replace('\:', ':')
    $buildTools = Get-ChildItem (Join-Path $sdkPath 'build-tools') -Directory |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (!$buildTools) { throw 'Android build-tools missing' }
    $apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $bridgeZip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $mobileRoot 'android\app\libs\hysteria_bridge.aar'))
    try {
        foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
            if (!($bridgeZip.Entries | Where-Object { $_.FullName -eq "jni/$abi/libhysteriabridge.so" })) {
                throw "Native bridge missing $abi; rebuild it before TV packaging"
            }
        }
    } finally { $bridgeZip.Dispose() }
    $versionLine = Get-Content (Join-Path $mobileRoot 'pubspec.yaml') |
        Where-Object { $_ -match '^version: ' } | Select-Object -First 1
    $versionName = ($versionLine -replace '^version: ', '').Split('+')[0]
    if ($versionName -notmatch '^\d+\.\d+\.\d+$') { throw 'TV preview requires a numeric version name' }
    New-Item -ItemType Directory -Path $tvOutput -Force | Out-Null
    $artifact = Join-Path $tvOutput "wavebreak-tv-$versionName-$BuildNumber-preview.apk"
    if (Test-Path -LiteralPath $artifact) { throw 'Preview already exists; use a new BuildNumber' }
    $oldAndroidHome = $env:ANDROID_HOME
    try {
        $env:ANDROID_HOME = $sdkPath
        Set-Location $mobileRoot
        Invoke-Checked $Flutter @('pub', 'get')
        Invoke-Checked $Flutter @('analyze', '--no-pub', 'lib/main_tv.dart', 'lib/features/tv', 'test/tv_app_test.dart')
        Invoke-Checked $Flutter @('test', '--no-pub')
        Invoke-Checked $Flutter @('build', 'apk', '--release', '--no-pub', '--target=lib/main_tv.dart',
            '--target-platform=android-arm,android-arm64,android-x64',
            "--build-name=$versionName", "--build-number=$BuildNumber",
            '--dart-define=FLAVOR=production', '--dart-define=CORE_BASE_URL=https://core.wavebreak.com.tr',
            '--dart-define=USE_MOCK_API=false', '--dart-define=USE_SIMULATED_VPN=false',
            '--dart-define=ACCESS_PROTOCOL=vless', '--dart-define=WAVEBREAK_TV=true')
        $apk = Join-Path $mobileRoot 'build\app\outputs\flutter-apk\app-release.apk'
        $certificate = & $apksigner verify --print-certs $apk
        if ($LASTEXITCODE -ne 0 -or !(($certificate -join "`n") -match 'd0d706bf9211d6a4c50e6a86742a2452eee650f0f3a4db5d5463a24b63cc57b6')) {
            throw 'TV APK signature does not match the WAVEBREAK release key'
        }
        $badging = & $aapt dump badging $apk
        if ($LASTEXITCODE -ne 0 -or !(($badging -join "`n") -match "name='com.wavebreak.wavebreak.tv'")) {
            throw 'TV package ID missing; refusing to deliver a phone APK'
        }
        if (!(($badging -join "`n") -match 'leanback-launchable-activity')) { throw 'TV launcher missing' }
        $apkZip = [System.IO.Compression.ZipFile]::OpenRead($apk)
        try {
            foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
                foreach ($lib in @('libflutter.so', 'libapp.so', 'libhysteriabridge.so')) {
                    if (!$apkZip.GetEntry("lib/$abi/$lib")) { throw "TV APK missing $abi/$lib" }
                }
            }
            $stream = $apkZip.GetEntry('lib/arm64-v8a/libapp.so').Open()
            $buffer = New-Object System.IO.MemoryStream
            try {
                $stream.CopyTo($buffer)
                $binary = [System.Text.Encoding]::ASCII.GetString($buffer.ToArray())
                if (!$binary.Contains('https://core.wavebreak.com.tr') -or $binary.Contains('127.0.0.1:18080')) {
                    throw 'TV APK does not use production Core'
                }
            } finally { $stream.Dispose(); $buffer.Dispose() }
        } finally { $apkZip.Dispose() }
        Copy-Item -LiteralPath $apk -Destination $artifact
        $sourceStatus = & git -C $projectRoot status --porcelain --untracked-files=normal
        [ordered]@{ package = 'com.wavebreak.wavebreak.tv'; preview = $true; version = $versionName;
            buildNumber = $BuildNumber; baseCommit = $localHead; sourceStatus = @($sourceStatus);
            sha256 = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash;
            abis = @('armeabi-v7a', 'arm64-v8a', 'x86_64'); deviceVerified = $false } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($artifact + '.json') -Encoding UTF8
        Write-Host "TV preview: $artifact (not published, device verification required)"
    } finally {
        $env:ANDROID_HOME = $oldAndroidHome
    }
} finally { Pop-Location }
