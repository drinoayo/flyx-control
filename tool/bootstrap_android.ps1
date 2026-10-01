param(
    [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"

function Require-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "'$name' was not found in PATH."
    }
}

Require-Command "flutter"
Require-Command "python"

Write-Host "Generating Android scaffold..."
flutter create . --platforms=android --project-name flyx_control --org com.flyxcontrol --no-pub

Write-Host "Applying FlyX local-router Android network configuration..."
python tool/apply_android_router_config.py

Write-Host "Applying FlyX Android home-screen widget configuration..."
python tool/apply_android_widget_config.py

$generatedTest = "test/widget_test.dart"
if (Test-Path $generatedTest) {
    $content = Get-Content $generatedTest -Raw
    if ($content -match "MyApp") {
        Remove-Item $generatedTest -Force
        Write-Host "Removed Flutter's generated placeholder widget test."
    }
}

if (-not $SkipPubGet) {
    Write-Host "Installing Flutter dependencies..."
    flutter pub get
}

Write-Host ""
Write-Host "Android setup complete."
Write-Host "Next: flutter analyze"
Write-Host "Then: flutter build apk --debug"
