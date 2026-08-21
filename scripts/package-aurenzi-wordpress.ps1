$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $root 'planner-frontend'
$wordpress = Join-Path $root 'wordpress'
$theme = Join-Path $wordpress 'wp-content\themes\aurenzi-twentytwentyfive'
$plugin = Join-Path $wordpress 'wp-content\plugins\aurenzi-storefront-bridge'
$dist = Join-Path $wordpress 'dist'

Push-Location $frontend
try {
    npm run wordpress:navigation:sync
} finally {
    Pop-Location
}

$images = Join-Path $theme 'assets\images'
New-Item -ItemType Directory -Force -Path $images | Out-Null
Copy-Item `
    -LiteralPath (Join-Path $frontend 'src\components\storefront\logo_aurenzi.svg') `
    -Destination (Join-Path $images 'logo_aurenzi.svg') `
    -Force

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$pluginZip = Join-Path $dist 'aurenzi-storefront-bridge.zip'
$themeZip = Join-Path $dist 'aurenzi-twentytwentyfive.zip'

foreach ($archive in @($pluginZip, $themeZip)) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive
    }
}

Push-Location (Split-Path $plugin -Parent)
try {
    Compress-Archive -Path (Split-Path $plugin -Leaf) -DestinationPath $pluginZip
} finally {
    Pop-Location
}

Push-Location (Split-Path $theme -Parent)
try {
    Compress-Archive -Path (Split-Path $theme -Leaf) -DestinationPath $themeZip
} finally {
    Pop-Location
}

Write-Host "Plugin: $pluginZip"
Write-Host "Theme:  $themeZip"
