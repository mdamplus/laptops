# =========================================
# Script: instalar-apps.ps1
# Objetivo: Instalar Bitdefender, GPT4All y Google Chrome
# Requisitos: Windows 10/11 con winget disponible
# =========================================

# 1. Verificar que se ejecuta como administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "⚠️ Ejecuta este script en PowerShell como Administrador." -ForegroundColor Red
    exit 1
}

# 2. Parámetros winget (sin prompts)
$wingetArgs = @(
    "--silent",
    "--accept-package-agreements",
    "--accept-source-agreements"
)

function Install-App {
    param(
        [string[]]$Ids,
        [string]$FriendlyName
    )

    foreach ($id in $Ids) {
        Write-Host "➡ Instalando $FriendlyName ($id)..." -ForegroundColor Cyan
        try {
            winget install --id $id @wingetArgs
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   ✅ $FriendlyName instalado con éxito ($id)" -ForegroundColor Green
                return
            }
        } catch {
            Write-Host "   ❌ Error instalando $FriendlyName con $id" -ForegroundColor Yellow
        }
    }
    Write-Host "⚠ No se pudo instalar $FriendlyName con los IDs probados." -ForegroundColor Red
}

# 3. Instalar aplicaciones
Install-App -Ids @("Google.Chrome","Google.ChromeEnterprise") -FriendlyName "Google Chrome"
Install-App -Ids @("Nomic.AI.GPT4All","Nomic.GPT4All") -FriendlyName "GPT4All"
Install-App -Ids @("Bitdefender.Bitdefender","Bitdefender.Agent","Bitdefender.VPN") -FriendlyName "Bitdefender"

Write-Host "`n🎉 Instalación completada." -ForegroundColor Green
Read-Host "Pulsa ENTER para salir..."
