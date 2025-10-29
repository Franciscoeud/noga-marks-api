# === Noga Marks Token Generator ===
# Genera token largo de Facebook/Instagram Graph API y extrae IDs clave

Write-Host "`n=== GENERADOR DE TOKEN LARGO (Noga Marks) ===`n"

# Paso 1: Ingreso de credenciales
$APP_ID = Read-Host "Ingresa tu APP_ID de Meta Developers"
$APP_SECRET = Read-Host "Ingresa tu APP_SECRET de Meta Developers"
$SHORT_TOKEN = Read-Host "Pega tu SHORT-LIVED TOKEN obtenido del Graph API Explorer"

# Paso 2: Generar el token largo
Write-Host "`nGenerando token largo..."
$exchangeUrl = "https://graph.facebook.com/v19.0/oauth/access_token?grant_type=fb_exchange_token&client_id=$APP_ID&client_secret=$APP_SECRET&fb_exchange_token=$SHORT_TOKEN"
try {
    $longResp = Invoke-RestMethod -Uri $exchangeUrl -Method GET
    $LONG_TOKEN = $longResp.access_token
    Write-Host "Token largo generado correctamente.`n"
} catch {
    Write-Host "Error al generar token largo:" $_.Exception.Message
    exit
}

# Paso 3: Obtener páginas del usuario
Write-Host "Obteniendo tus páginas vinculadas..."
try {
    $pages = Invoke-RestMethod -Uri "https://graph.facebook.com/v19.0/me/accounts?fields=id,name,instagram_business_account" `
        -Headers @{ Authorization = "Bearer $LONG_TOKEN" }
    foreach ($p in $pages.data) {
        Write-Host "Página:" $p.name "→ ID:" $p.id
        if ($p.instagram_business_account) {
            Write-Host "Cuenta IG vinculada:" $p.instagram_business_account.username "→ IG_ID:" $p.instagram_business_account.id "`n"
        }
    }
} catch {
    Write-Host "Error al obtener páginas o cuentas de Instagram."
    exit
}

# Paso 4: Elegir la página para el token largo
$PAGE_ID = Read-Host "Ingresa el PAGE_ID de la página que quieres usar"
Write-Host "`nGenerando PAGE TOKEN largo..."
try {
    $pageResp = Invoke-RestMethod -Uri "https://graph.facebook.com/v19.0/$PAGE_ID?fields=access_token" `
        -Headers @{ Authorization = "Bearer $LONG_TOKEN" }
    $PAGE_TOKEN = $pageResp.access_token
    Write-Host "Page Token generado correctamente.`n"
} catch {
    Write-Host "Error al obtener el Page Token:" $_.Exception.Message
    exit
}

# Paso 5: Confirmar IG Business ID
$IG_ID = Read-Host "Ingresa el IG_BUSINESS_ID (si lo viste antes, si no presiona Enter)"
if (-not $IG_ID) {
    try {
        $igLookup = Invoke-RestMethod -Uri "https://graph.facebook.com/v19.0/$PAGE_ID?fields=instagram_business_account" `
            -Headers @{ Authorization = "Bearer $PAGE_TOKEN" }
        $IG_ID = $igLookup.instagram_business_account.id
        Write-Host "IG_BUSINESS_ID detectado automáticamente: $IG_ID"
    } catch {
        Write-Host "No se pudo detectar el IG Business ID automáticamente."
    }
}

# Paso 6: Mostrar resultados finales
Write-Host "`n=== RESULTADOS ==="
Write-Host "LONG_TOKEN: $LONG_TOKEN"
Write-Host "PAGE_ID: $PAGE_ID"
Write-Host "PAGE_TOKEN: $PAGE_TOKEN"
Write-Host "IG_BUSINESS_ID: $IG_ID"
Write-Host "`nGuarda estos valores en tu archivo .env como:"
Write-Host "`n--------------------------------------"
Write-Host "IG_ACCESS_TOKEN=$PAGE_TOKEN"
Write-Host "IG_BUSINESS_ID=$IG_ID"
Write-Host "--------------------------------------`n"
Write-Host "Recuerda: este token dura 60 días. Puedes renovarlo ejecutando este script nuevamente.`n"
