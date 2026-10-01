param(
    [string]$Alias = "flyx-beta"
)

$ErrorActionPreference = "Stop"
$keystore = Join-Path $PSScriptRoot "flyx-beta.jks"
$base64File = Join-Path $PSScriptRoot "flyx-beta-keystore-base64.txt"

if (Test-Path $keystore) {
    throw "A beta keystore already exists at $keystore. Keep the existing key; replacing it would break in-place updates."
}

function Read-PlainSecret([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

$storePassword = Read-PlainSecret "Choose a keystore password"
$keyPassword = Read-PlainSecret "Choose a key password"

if ([string]::IsNullOrWhiteSpace($storePassword) -or [string]::IsNullOrWhiteSpace($keyPassword)) {
    throw "Passwords cannot be empty."
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    throw "keytool was not found. Install/use the JDK that comes with Android Studio and run this script again."
}

& $keytool.Source -genkeypair -v -keystore $keystore -storepass $storePassword -keypass $keyPassword -alias $Alias -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=FlyX Control Beta, OU=Beta, O=FlyX Control, L=Osogbo, ST=Osun, C=NG"

if ($LASTEXITCODE -ne 0) {
    throw "keytool failed with exit code $LASTEXITCODE"
}

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))
[IO.File]::WriteAllText($base64File, $base64)

Write-Host ""
Write-Host "Stable beta signing key created."
Write-Host "Keep $keystore private and backed up."
Write-Host ""
Write-Host "Add these GitHub Actions repository secrets:"
Write-Host "  FLYX_BETA_KEYSTORE_B64   = contents of $base64File"
Write-Host "  FLYX_BETA_STORE_PASSWORD = the keystore password you entered"
Write-Host "  FLYX_BETA_KEY_ALIAS      = $Alias"
Write-Host "  FLYX_BETA_KEY_PASSWORD   = the key password you entered"
Write-Host ""
Write-Host "Do not commit the .jks or base64 file."
