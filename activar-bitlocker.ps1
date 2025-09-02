# =========================================
# Script: Activar BitLocker en C:
# - Cifra el disco con XTS-AES-256
# - Guarda clave en OneDrive (si existe) o D:\ClavesBitlocker
# Ejecutar como Administrador
# =========================================

$ErrorActionPreference = 'Stop'

# --- Comprobar si es Admin ---
$curr = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $curr.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Este script debe ejecutarse como Administrador." -ForegroundColor Red
    exit
}

Write-Host "==> Preparando BitLocker en C: ..." -ForegroundColor Magenta

# --- Detectar carpeta OneDrive ---
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

# Seleccionar carpeta destino
$KeyDir = $KeyDirOneDrive
if (-not $KeyDir) { $KeyDir = $KeyDirFallback }

# Crear carpeta si no existe
if (-not (Test-Path $KeyDir)) { New-Item -ItemType Directory -Path $KeyDir | Out-Null }

Write-Host ("Guardando claves en: {0}" -f $KeyDir) -ForegroundColor Cyan

# --- Activar BitLocker ---
try {
    $vol = Get-BitLockerVolume -MountPoint "C:"
    if ($vol -and $vol.ProtectionStatus -eq "On") {
        Write-Host "BitLocker ya esta activo en C:. Exportando clave..." -ForegroundColor Yellow
    } else {
        Write-Host "Activando BitLocker en C: (XTS-AES-256, cifrado rapido)..." -ForegroundColor Cyan
        Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector -Verbose
    }

    # Obtener protector de recuperacion
    $vol = Get-BitLockerVolume -MountPoint "C:"
    $rk = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    if (-not $rk) {
        $rk = (Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector).KeyProtector
    }

    # Guardar clave en archivo
    $Computer  = $env:COMPUTERNAME
    $TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
    $KeyFile   = Join-Path $KeyDir ("BitLocker_Recovery_" + $Computer + "_" + $TimeStamp + ".txt")

@"
Equipo: $Computer
Fecha:  $(Get-Date)
Unidad: C:
Tipo protector: RecoveryPassword
ID protector:  $($rk.KeyProtectorId)
Contrasena de recuperacion:
$($rk.RecoveryPassword)
"@ | Out-File -FilePath $KeyFile -Encoding UTF8 -Force

    Write-Host ("Clave de recuperacion guardada en: {0}" -f $KeyFile) -ForegroundColor Green
    Write-Host "Si la ruta es OneDrive, se sincronizara automaticamente." -ForegroundColor DarkCyan

} catch {
    Write-Host ("Error en BitLocker: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

Write-Host ""
Write-Host "✅ BitLocker configurado. Reinicia para iniciar el cifrado en segundo plano." -ForegroundColor Green
Read-Host "Pulsa ENTER para cerrar esta ventana..."
