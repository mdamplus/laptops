# =========================================
# IDT Lab + MDAM Plus for Arrabal AID :)
# Setup Aula Windows 11
#  - Instala aplicaciones (winget)
#  - Crea usuario local "Aula" (estandar)
#  - Activa BitLocker en C: y guarda clave en OneDrive (o fallback)
#  Ejecutar como Administrador
# =========================================

$ErrorActionPreference = 'Stop'

# --- Auto-elevacion: relanzar como admin si no lo es ---
$curr = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $curr.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } catch {
        Write-Host "No se pudo solicitar elevacion: $($_.Exception.Message)" -ForegroundColor Red
    }
    exit
}

# --- Transcript / log ---
try {
    $TranscriptPath = "$env:Public\setup-aula-log.txt"
    Start-Transcript -Path $TranscriptPath -Append | Out-Null
    Write-Host "Registrando log en: $TranscriptPath" -ForegroundColor DarkCyan
} catch {
    Write-Host "No se pudo iniciar el transcript: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Utilidades winget ---
$wingetArgs = @("--silent","--accept-package-agreements","--accept-source-agreements")

function Install-App {
    param(
        [Parameter(Mandatory=$true)][string[]]$Ids,
        [string]$FriendlyName = "Aplicacion"
    )
    foreach ($id in $Ids) {
        Write-Host ("Instalando {0} ({1})..." -f $FriendlyName, $id) -ForegroundColor Cyan
        try {
            winget install --id $id @wingetArgs
            if ($LASTEXITCODE -eq 0) {
                Write-Host ("OK {0} instalado con {1}" -f $FriendlyName, $id) -ForegroundColor Green
                return $true
            } else {
                Write-Host ("winget retorno codigo {0} para {1}" -f $LASTEXITCODE, $id) -ForegroundColor Yellow
            }
        } catch {
            Write-Host ("Fallo instalando {0} con {1}: {2}" -f $FriendlyName, $id, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    Write-Host ("No se pudo instalar {0} con IDs: {1}" -f $FriendlyName, ($Ids -join ', ')) -ForegroundColor Yellow
    return $false
}

# --- 1) Actualizar winget / paquetes ---
try {
    Write-Host ""
    Write-Host "==> Actualizando paquetes con winget..." -ForegroundColor Magenta
    winget upgrade --all @wingetArgs | Out-Null
} catch {
    Write-Host ("Aviso: winget upgrade fallo: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

# --- 2) Instalar aplicaciones ---
Write-Host ""
Write-Host "==> Instalando aplicaciones..." -ForegroundColor Magenta

Install-App -Ids @(
    'Microsoft.Edge'
) -FriendlyName 'Microsoft Edge' | Out-Null

Install-App -Ids @(
    'Google.Chrome',
    'Google.ChromeEnterprise'
) -FriendlyName 'Google Chrome' | Out-Null

Install-App -Ids @(
    'Mozilla.Firefox.DeveloperEdition'
) -FriendlyName 'Firefox Developer Edition' | Out-Null

Install-App -Ids @(
    'Microsoft.Teams',
    'Microsoft.Teams.Classic'
) -FriendlyName 'Microsoft Teams' | Out-Null

Install-App -Ids @(
    'Zoom.Zoom'
) -FriendlyName 'Zoom' | Out-Null

Install-App -Ids @(
    'Bitdefender.Bitdefender',
    'Bitdefender.Agent',
    'Bitdefender.VPN'
) -FriendlyName 'Bitdefender (ver edicion)' | Out-Null

Install-App -Ids @(
    'Nomic.AI.GPT4All',
    'Nomic.GPT4All'
) -FriendlyName 'GPT4All' | Out-Null

# --- 3) Crear/ajustar usuario local "Aula" (estandar) ---
Write-Host ""
Write-Host "==> Creando/ajustando usuario 'Aula'..." -ForegroundColor Magenta

$AulaUser = "Aula"
$AulaPassPlain = "Aula_2025!"   # CAMBIAR SEGUN POLITICA DEL CENTRO
$AulaPass = ConvertTo-SecureString $AulaPassPlain -AsPlainText -Force

try {
    $existing = Get-LocalUser -Name $AulaUser -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Usuario 'Aula' ya existe; actualizando parametros..." -ForegroundColor Yellow
        Set-LocalUser -Name $AulaUser -Password $AulaPass -PasswordNeverExpires $true
    } else {
        New-LocalUser -Name $AulaUser -Password $AulaPass -FullName "Usuario Aula" -Description "Cuenta estandar para alumnos" -PasswordNeverExpires $true | Out-Null
    }

    try { Remove-LocalGroupMember -Group "Administrators" -Member $AulaUser -ErrorAction SilentlyContinue } catch {}
    try { Add-LocalGroupMember -Group "Users" -Member $AulaUser -ErrorAction SilentlyContinue } catch {}

    Write-Host "Usuario 'Aula' OK (estandar)." -ForegroundColor Green
} catch {
    Write-Host ("Error creando/ajustando usuario 'Aula': {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# --- 4) BitLocker: activar en C: y guardar clave en OneDrive (o fallback) ---
Write-Host ""
Write-Host "==> BitLocker: preparacion de clave y activacion..." -ForegroundColor Magenta

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

$KeyDir = $null
try {
    if ($KeyDirOneDrive) {
        if (-not (Test-Path $KeyDirOneDrive)) { New-Item -ItemType Directory -Path $KeyDirOneDrive | Out-Null }
        $KeyDir = $KeyDirOneDrive
        Write-Host ("OneDrive detectado: {0}" -f $KeyDir) -ForegroundColor Green
    } else {
        if (-not (Test-Path $KeyDirFallback)) { New-Item -ItemType Directory -Path $KeyDirFallback | Out-Null }
        $KeyDir = $KeyDirFallback
        Write-Host ("OneDrive no detectado; usando carpeta de respaldo: {0}" -f $KeyDir) -ForegroundColor Yellow
    }
} catch {
    Write-Host ("Error preparando carpetas de clave: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $KeyDir = $KeyDirFallback
}

try {
    $vol = Get-BitLockerVolume -MountPoint "C:"
    if ($vol -and $vol.ProtectionStatus -eq "On") {
        Write-Host "BitLocker ya esta activo en C:. Exportando/confirmando clave..." -ForegroundColor Yellow
    } else {
        Write-Host "Activando BitLocker en C: (XTS-AES-256, UsedSpaceOnly)..." -ForegroundColor Cyan
        Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector -Verbose
    }

    $vol = Get-BitLockerVolume -MountPoint "C:"
    $rk = $null
    if ($vol -and $vol.KeyProtector) {
        $rk = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
    }
    if (-not $rk) {
        $rk = (Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector).KeyProtector
    }

    $Computer  = $env:COMPUTERNAME
    $TimeStamp = (Get-Date -Format "yyyyMMdd_HHmmss")
    $KeyFile   = Join-Path $KeyDir ("BitLocker_Recovery_" + $Computer + "_" + $TimeStamp + ".txt")

    $content = @()
    $content += "Equipo: $Computer"
    $content += "Fecha:  $(Get-Date)"
    $content += "Unidad: C:"
    $content += "Tipo protector: RecoveryPassword"
    $content += "ID protector:  $($rk.KeyProtectorId)"
    $content += "Contrasena de recuperacion:"
    $content += "$($rk.RecoveryPassword)"
    $content -join "`r`n" | Out-File -FilePath $KeyFile -Encoding UTF8 -Force

    Write-Host ("Clave de recuperacion guardada en: {0}" -f $KeyFile) -ForegroundColor Green
    Write-Host "Si la ruta es OneDrive, se sincronizara automaticamente." -ForegroundColor DarkCyan

} catch {
    Write-Host ("Error durante activacion/backup de BitLocker: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# --- Fin ---
Write-Host ""
Write-Host "Configuracion completada. Reinicia para iniciar el cifrado de BitLocker en segundo plano." -ForegroundColor Green

try { Stop-Transcript | Out-Null } catch {}
Read-Host "Pulsa ENTER para cerrar esta ventana..."
