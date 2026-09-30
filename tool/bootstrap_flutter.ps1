$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter is not installed or not on PATH."
}

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Tmp = Join-Path $env:TEMP ("flyx_control_" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $Tmp | Out-Null

Copy-Item -Recurse (Join-Path $Root "lib") (Join-Path $Tmp "lib")
Copy-Item (Join-Path $Root "pubspec.yaml") $Tmp
Copy-Item (Join-Path $Root "analysis_options.yaml") $Tmp

Push-Location $Root
try {
  flutter create --project-name flyx_control --org com.etchpoint.flyxcontrol --platforms=android,ios .
  Remove-Item -Recurse -Force (Join-Path $Root "lib")
  Copy-Item -Recurse (Join-Path $Tmp "lib") (Join-Path $Root "lib")
  Copy-Item (Join-Path $Tmp "pubspec.yaml") $Root -Force
  Copy-Item (Join-Path $Tmp "analysis_options.yaml") $Root -Force
  flutter pub get
} finally {
  Pop-Location
  Remove-Item -Recurse -Force $Tmp
}

Write-Host "Flutter platform shells generated. Apply the local-network settings in platform_patches/ and README.md before running on a device."
