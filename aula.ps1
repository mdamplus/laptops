# =========================================
# IDT Lab + MDAM Plus for Arrabal AID :)
# =========================================
# Setup Aula Windows 11
#  - Instala aplicaciones (winget)
#  - Crea usuario local "Aula" (estándar)
#  - Activa BitLocker en C: y guarda clave en OneDrive (o fallback)
#  Ejecutar como Administrador
# =========================================

# --- Auto-elevación, transcript y entorno ---
$ErrorActionPreference = 'Stop'

# Si no está elevado, relanzar como Administrador
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } catch {
        Write-Host "No se pudo solicitar elevación: $($_.Exception.Message)" -ForegroundColor Red
    }
    exit
}

# Inicia transcript (log)
try {
    $TranscriptPath = "$env:Public\setup-aula-log.txt"
    Start-Transcript -Path $TranscriptPath -Append | Out-Null
    Write-Host "📝 Registrando log en: $TranscriptPath" -ForegroundColor DarkCyan
} catch {
    Write-Host "⚠ No se pudo iniciar el transcript: $($_.Exception.Message)" -ForegroundColor Yellow
}

# -------------------------------------------------------------
# Utilidades
# -------------------------------------------------------------

# Evitar prompts de winget
$wingetArgs = @("--silent","--accept-package-agreements","--accept-source-agreements")

function Install-App {
    param(
        [Parameter(Mandatory=$true)][string[]]$Ids,
        [string]$FriendlyName = "Aplicación"
    )
    foreach ($id in $Ids) {
        Write-Host "• Instalando $FriendlyName ($id)..." -ForegroundColor Cyan
        try {
            winget install --id $id @wingetArgs
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ $FriendlyName instalado con $id" -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Host "  ↪ intento con siguiente ID (error: $($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
    Write-Host "  ⚠ No se pudo instalar $FriendlyName con los IDs probados: $($Ids -join ', ')" -ForegroundColor Yellow
    return $false
}

# -------------------------------------------------------------
# 1) Actualiza winget y fuentes
# -------------------------------------------------------------
try {
    Write-Host "`n==> Actualizando paquetes con winget..." -ForegroundColor Magenta
    winget upgrade --all @wingetArgs | Out-Null
} catch {
    Write-Host "⚠ winget upgrade falló: $($_.Exception.Message)" -ForegroundColor Yellow
}

# -------------------------------------------------------------
# 2) Instalación de aplicaciones
# -------------------------------------------------------------
Write-Host "`n==> Instalando aplicaciones..." -ForegroundColor Magenta

# Edge (suele venir instalado; lo incluimos por si acaso)
Install-App -Ids @("Microsoft.Edge") -FriendlyName "Microsoft Edge" | Out-Null

Install-App -Ids @("Google.Chrome","Google.ChromeEnterprise") -FriendlyName "Google Chrome" | Out-Null
Install-App -Ids @("Mozilla.Firefox.DeveloperEdition") -FriendlyName "Firefox Developer Edition" | Out-Null
Install-App -Ids @("Microsoft.Teams","Microsoft.Teams.Classic") -FriendlyName "Microsoft Teams" | Out-Null
Install-App -Ids @("Zoom.Zoom") -FriendlyName "Zoom" | Out-Null

# Bitdefender: el ID exacto depende de edición/portal. Probar comunes.
# Si tu edición requiere instalador propio, añade aquí la descarga y ejecuta con /quiet o /silent.
Install-App -Ids @("Bitdefender.Bitdefender","Bitdefender.Agent","Bitdefender.VPN") -FriendlyName "Bitdefender (ver edición)" | Out-Null

Install-App -Ids @("Nomic.AI.GPT4All","Nomic.GPT4All") -FriendlyName "GPT4All" | Out-Null

# -------------------------------------------------------------
# 3) Crear/ajustar usuario local "Aula" (estándar)
# -------------------------------------------------------------
Write-Host "`n==> Creando/ajustando usuario 'Aula'..." -ForegroundColor Magenta

$AulaUser = "Aula"
$AulaPassPlain = "Aula_2025!"   # <-- CAMBIA ESTA CONTRASEÑA SEGÚN POLÍTICA DEL CENTRO
$AulaPass = ConvertTo-SecureString $AulaPassPlain -AsPlainText -Force

try {
    if (Get-LocalUser -Name $AulaUser -ErrorAction SilentlyContinue) {
        Write-Host "Usuario '$AulaUser' ya existe; actualizando parámetros..." -ForegroundColor Yellow
        Set-LocalUser -Name $AulaUser -Password $AulaPass -PasswordNeverExpires $true
    } else {
        New-LocalUser -Name $AulaUser -Password $AulaPass -FullName "Usuario Aula" -Description "Cuenta estándar para alumnos" -PasswordNeverExpires $true | Out-Null
    }

    # Garantiza que NO sea administrador
    try { Remove-LocalGroupMember -Group "Administrators" -Member $AulaUser -ErrorAction SilentlyContinue } catch {}
    # Garantiza que esté en 'Users'
    try { Add-LocalGroupMember -Group "Users" -Member $AulaUser -ErrorAction SilentlyContinue } catch {}

    Write-Host "✓ Usuario 'Aula' creado/actualizado como estándar." -ForegroundColor Green
} catch {
    Write-Host "❌ Error creando/ajustando usuario 'Aula': $($_.Exception.Message)" -ForegroundColor Red
}

# -------------------------------------------------------------
# 4) BitLocker: activar en C: y guardar clave en OneDrive (o fallback)
# -------------------------------------------------------------
Write-Host "`n==> BitLocker: preparación de clave y activación..." -ForegroundColor Magenta

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

try {
    if ($KeyDirOneDrive) {
        if (!(Test-Path $KeyDirOneDrive)) { New-Item -ItemType Directory -Path $KeyDirOneDrive | Out-Null }
        $KeyDir = $KeyDirOneDrive
        Write-Host "OneDrive detectado: $KeyDir" -ForegroundColor Green
    } else {
        if (!(Test-Path $KeyDirFallback)) { New-Item -ItemType Directory -Path $KeyDirFallback | Out-Null }
        $KeyDir = $KeyDirFallback
        Write-Host "⚠ OneDrive no detectado; usando carpeta de respaldo: $KeyDir" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Error preparando carpetas de clave: $($_.Exception.Message)" -ForegroundColor Red
    $KeyDir = $KeyDirFallback
}

# Activar BitLocker si no está activo
try {
    $vol = Get-BitLockerVolume -MountPoint "C:"
    if ($vol.ProtectionStatus -eq "On") {
        Write-Host "BitLocker ya está activo en C:. Exportando/confirmando clave de recuperación..." -ForegroundColor Yellow
    } else {
        Write-Host "Activando BitLocker en C: (XTS-AES-256, solo espacio usado)..." -ForegroundColor Cyan
        Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector -Verbose
    }

    # Releer y obtener protector de recuperación
    $vol = Get-BitLockerVolume -MountPoint "C:"
    $rk  = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    if (-not $rk) {
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
    Write-Host "ℹ Si la ruta es OneDrive, se sincronizará automáticamente." -ForegroundColor DarkCyan

} catch {
    Write-Host "❌ Error durante la activación/backup de BitLocker: $($_.Exception.Message)" -ForegroundColor Red
}

# -------------------------------------------------------------
# Fin
# -------------------------------------------------------------
Write-Host "`n✅ Configuración completada. Se recomienda REINICIAR ahora para que el cifrado de BitLocker comience en segundo plano." -ForegroundColor Green

try { Stop-Transcript | Out-Null } catch {}
Read-Host "Pulsa ENTER para cerrar esta ventana..."
