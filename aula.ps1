# =========================================
# IDT Lab + MDAM Plus for Arrabal AID :)
# =========================================
# =========================================
#  Setup Aula Windows 11
#  - Instala aplicaciones (winget)
#  - Crea usuario local "Aula" (estándar)
#  - Activa BitLocker en C: y guarda clave en OneDrive (o fallback)
#  Ejecutar como Administrador
# =========================================

# --- Utilidades ---
function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Este script debe ejecutarse como Administrador." -ForegroundColor Yellow
        exit 1
    }
}
Ensure-Admin

# Evitar prompts de winget
$wingetArgs = @("--silent","--accept-package-agreements","--accept-source-agreements")

function Install-App {
    param(
        [Parameter(Mandatory=$true)][string[]]$Ids,
        [string]$FriendlyName
    )
    foreach ($id in $Ids) {
        Write-Host "• Instalando $FriendlyName ($id)..." -ForegroundColor Cyan
        try {
            winget install --id $id @wingetArgs
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ $FriendlyName instalado con $id" -ForegroundColor Green
                return
            }
        } catch {
            # seguir con el siguiente id
        }
    }
    Write-Host "  ⚠ No se pudo instalar $FriendlyName con los IDs probados: $($Ids -join ', ')" -ForegroundColor Yellow
}

# --- 1) Actualiza winget y fuentes ---
try {
    Write-Host "Actualizando paquetes existentes con winget..." -ForegroundColor Cyan
    winget upgrade --all @wingetArgs
} catch {}

# --- 2) Instalación de aplicaciones ---
# Edge normalmente viene instalado; lo incluimos por si acaso
Install-App -Ids @("Microsoft.Edge") -FriendlyName "Microsoft Edge"

Install-App -Ids @("Google.Chrome","Google.ChromeEnterprise") -FriendlyName "Google Chrome"
Install-App -Ids @("Mozilla.Firefox.DeveloperEdition") -FriendlyName "Firefox Developer Edition"
Install-App -Ids @("Microsoft.Teams","Microsoft.Teams.Classic") -FriendlyName "Microsoft Teams"
Install-App -Ids @("Zoom.Zoom") -FriendlyName "Zoom"
# Bitdefender: según edición, el ID puede cambiar o requerir instalador de su portal.
# Probamos IDs comunes; si no, descarga manualmente su instalador corporativo/retail y ejecútalo en este script.
Install-App -Ids @("Bitdefender.Bitdefender","Bitdefender.Agent","Bitdefender.VPN") -FriendlyName "Bitdefender (ver edición)"
Install-App -Ids @("Nomic.AI.GPT4All","Nomic.GPT4All") -FriendlyName "GPT4All"

# --- 3) Crear usuario local "Aula" (estándar) ---
# Define aquí la contraseña deseada del usuario Aula (cámbiala por la política del centro)
$AulaUser = "Aula"
$AulaPassPlain = "Aula_2025!"   # <-- CAMBIA ESTA CONTRASEÑA
$AulaPass = ConvertTo-SecureString $AulaPassPlain -AsPlainText -Force

if (Get-LocalUser -Name $AulaUser -ErrorAction SilentlyContinue) {
    Write-Host "Usuario '$AulaUser' ya existe; actualizando parámetros..." -ForegroundColor Yellow
    Set-LocalUser -Name $AulaUser -Password $AulaPass -PasswordNeverExpires $true
} else {
    New-LocalUser -Name $AulaUser -Password $AulaPass -FullName "Usuario Aula" -Description "Cuenta estándar para alumnos" -PasswordNeverExpires $true
}
# Garantiza que NO sea administrador
try {
    Remove-LocalGroupMember -Group "Administrators" -Member $AulaUser -ErrorAction SilentlyContinue
} catch {}
# Garantiza que esté en 'Users'
try {
    Add-LocalGroupMember -Group "Users" -Member $AulaUser -ErrorAction SilentlyContinue
} catch {}

Write-Host "✓ Usuario 'Aula' creado/actualizado como estándar." -ForegroundColor Green

# --- (Opcional) endurecimiento básico útil en aula ---
# Bloquear ejecución desde Descargas vía SRP/AppLocker requiere más preparación; se puede añadir después si quieres.
# Aquí nos centramos en el cifrado.

# --- 4) BitLocker: activar en C: y guardar clave en OneDrive (o fallback) ---
Write-Host "Preparando guardado de clave de recuperación en OneDrive (si disponible)..." -ForegroundColor Cyan

# Detecta carpeta OneDrive del administrador actual
$OneDrivePath = $null
try {
    $OneDrivePath = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\OneDrive' -ErrorAction Stop).UserFolder
} catch {
    $OneDrivePath = $env:OneDrive
}

$KeyDirOneDrive = $null
if ($OneDrivePath -and (Test-Path $OneDrivePath)) {
    $KeyDirOneDrive = Join-Path $OneDrivePath "BitLocker-Keys"
}
$KeyDirFallback = "D:\ClavesBitlocker"

if ($KeyDirOneDrive) {
    if (!(Test-Path $KeyDirOneDrive)) { New-Item -ItemType Directory -Path $KeyDirOneDrive | Out-Null }
    $KeyDir = $KeyDirOneDrive
    Write-Host "OneDrive detectado: $KeyDir" -ForegroundColor Green
} else {
    if (!(Test-Path $KeyDirFallback)) { New-Item -ItemType Directory -Path $KeyDirFallback | Out-Null }
    $KeyDir = $KeyDirFallback
    Write-Host "⚠ OneDrive no detectado; usando carpeta de respaldo: $KeyDir" -ForegroundColor Yellow
}

# Habilita BitLocker (si no lo está)
$vol = Get-BitLockerVolume -MountPoint "C:"
if ($vol.ProtectionStatus -eq "On") {
    Write-Host "BitLocker ya está activo en C:. Exportando/confirmando clave de recuperación..." -ForegroundColor Yellow
} else {
    Write-Host "Activando BitLocker en C: (XTS-AES-256, solo espacio usado)..." -ForegroundColor Cyan
    Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector -Verbose
}

# Obtiene la contraseña de recuperación y la guarda en archivo
$vol = Get-BitLockerVolume -MountPoint "C:"
$rk  = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

if (-not $rk) {
    # Si no existiera (poco probable), añadimos un protector de recuperación
    $rk = (Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector).KeyProtector
}

$Computer  = $env:COMPUTERNAME
$TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
$KeyFile   = Join-Path $KeyDir ("BitLocker_Recovery_" + $Computer + "_" + $TimeStamp + ".txt")

@"
Equipo: $Computer
Fecha:  $(Get-Date)
Unidad: C:
Tipo protector: RecoveryPassword
ID protector:  $($rk.KeyProtectorId)
Contraseña de recuperación:
$($rk.RecoveryPassword)
"@ | Out-File -FilePath $KeyFile -Encoding UTF8 -Force

Write-Host "✓ Clave de recuperación guardada en: $KeyFile" -ForegroundColor Green
Write-Host "ℹ Si la ruta es OneDrive, se sincronizará automáticamente cuando OneDrive esté activo." -ForegroundColor DarkCyan

Write-Host "`n✅ Configuración completada. Se recomienda REINICIAR ahora para que el cifrado de BitLocker comience en segundo plano." -ForegroundColor Green
