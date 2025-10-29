# test-lead.ps1 — Enviar lead de prueba al endpoint /leads (compatible con PowerShell)

# Configura tu endpoint local o de ngrok
$apiUrl = "http://127.0.0.1:8000/leads"

# Datos del lead de prueba
$lead = @{
    source  = "instagram"
    name    = "Maria Flores"
    email   = "maria@test.com"
    phone   = "+51987654321"
    message = "Hola, quiero saber mas de sus productos"
}

# Convertir a JSON
$jsonBody = $lead | ConvertTo-Json -Depth 5

Write-Host "Enviando lead de prueba a $apiUrl..."
Write-Host "Payload:" $jsonBody

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method POST -Body $jsonBody -ContentType "application/json"
    Write-Host "Lead registrado correctamente en Supabase:"
    $response | ConvertTo-Json -Depth 5
}
catch {
    Write-Host "Error al enviar lead:"
    Write-Host $_.Exception.Message
}
