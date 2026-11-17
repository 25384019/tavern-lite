# 出包脚本：固定用项目要求的 SDK，不吃 PATH 上的旧 Flutter。
#
#   pwsh -File tool\build.ps1              # 三个 ABI + 通用包
#   pwsh -File tool\build.ps1 -Split       # 只要三个分架构包
#   pwsh -File tool\build.ps1 -Universal   # 只要通用包
#
# 本机 PATH 上的 flutter 是 3.44.8 / Dart 3.12.2，低于 pubspec 的 sdk: ^3.13.5，
# 直接 `flutter build` 会失败——而且**不要**通过降低约束来绕过：那会改写 pubspec.lock
# 的解析结果，改回来之后依赖可能已经和原来不是一套。

param(
    [switch]$Split,
    [switch]$Universal
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root 'app'
$Flutter = 'E:\dshgo\sdk\flutter\bin\flutter.bat'
$JavaHome = 'C:\Program Files\Java\jdk-17'

if (-not (Test-Path -LiteralPath $Flutter)) {
    throw "找不到 Flutter：$Flutter —— 按 docs/BUILD.md 装 3.50.0 到那个位置。"
}

$version = & $Flutter --version 2>&1 | Select-Object -First 1
Write-Host "SDK: $version"
if ($version -notmatch '3\.50') {
    Write-Warning "这个 SDK 不是项目要求的 3.50.0；如果构建失败，先确认路径。"
}

$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
if (Test-Path -LiteralPath $JavaHome) { $env:JAVA_HOME = $JavaHome }

Push-Location $App
try {
    if (-not $Split -and -not $Universal) { $Split = $true; $Universal = $true }

    & $Flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 有错误，先修。' }

    & $Flutter test
    if ($LASTEXITCODE -ne 0) { throw '单测没过，先修。' }

    if ($Split) {
        & $Flutter build apk --release --split-per-abi
        if ($LASTEXITCODE -ne 0) { throw '分架构包构建失败。' }
    }
    if ($Universal) {
        & $Flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw '通用包构建失败。' }
    }

    $out = Join-Path $App 'build\app\outputs\flutter-apk'
    Get-ChildItem -LiteralPath $out -Filter '*.apk' |
        Sort-Object Name |
        ForEach-Object { '{0,-42} {1,6:N1} MB' -f $_.Name, ($_.Length / 1MB) }
} finally {
    Pop-Location
}
