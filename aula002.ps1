# =========================================
# Setup Aula Windows 11
# - Actualiza Windows Update
# - Instala aplicaciones (winget)
# - Crea usuario local "Aula" (estandar)
# - Activa BitLocker en C: y guarda clave en OneDrive (o fallback)
# Ejecutar como Administrador
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
            }
        } catch {
            Write-Host ("Fallo instalando {0} con {1}: {2}" -f $FriendlyName, $id, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    Write-Host ("No se pudo instalar {0} con IDs: {1}" -f $FriendlyName, ($Ids -join ', ')) -ForegroundColor Yellow
    return $false
}

# --- 1) Actualizar Windows Update ---
Write-Host ""
Write-Host "==> Ejecutando actualizacion de Windows Update..." -ForegroundColor Magenta
try {
    Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -Confirm:$false -ErrorAction SilentlyContinue
    Import-Module PSWindowsUpdate
    Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot
    Write-Host "Windows Update ejecutado. Si hay reinicios pendientes, hacerlo manualmente." -ForegroundColor Green
} catch {
    Write-Host "No se pudo ejecutar Windows Update via PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- 2) Instalar aplicaciones ---
Write-Host ""
Write-Host "==> Instalando aplicaciones..." -ForegroundColor Magenta

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
    'AnyDeskSoftwareGmbH.AnyDesk'
) -FriendlyName 'AnyDesk' | Out-Null

Install-App -Ids @(
    'Microsoft.VCRedist.2015+.x64'
) -FriendlyName 'Visual C++ Redistributable 2015-2022 (x64)' | Out-Null

Install-App -Ids @(
    'Microsoft.VCRedist.2015+.x86'
) -FriendlyName 'Visual C++ Redistributable 2015-2022 (x86)' | Out-Null

Install-App -Ids @(
    'Microsoft.DotNet.DesktopRuntime.8' # ultima LTS a fecha actual
) -FriendlyName '.NET Desktop Runtime' | Out-Null

Install-App -Ids @(
    'Bitdefender.Bitdefender',
    'Bitdefender.Agent',
    'Bitdefender.VPN'
) -FriendlyName 'Bitdefender (ver edicion)' | Out-Null

Install-App -Ids @(
    'Nomic.AI.GPT4All',
    'Nomic.GPT4All'
) -FriendlyName 'GPT4All' | Out-Null

# --- 3) Crear/ajustar usuario local "Aula" ---
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

# --- 4) BitLocker ---
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

$KeyDir = $KeyDirOneDrive
if (-not $KeyDir) { $KeyDir = $KeyDirFallback }

if (-not (Test-Path $KeyDir)) { New-Item -ItemType Directory -Path $KeyDir | Out-Null }

try {
    $vol = Get-BitLockerVolume -MountPoint "C:"
    if (-not $vol -or $vol.ProtectionStatus -ne "On") {
        Write-Host "Activando BitLocker en C:..." -ForegroundColor Cyan
        Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -UsedSpaceOnly -RecoveryPasswordProtector -Verbose
    }
    $vol = Get-BitLockerVolume -MountPoint "C:"
    $rk = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }
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
Contrasena de recuperacion:
$($rk.RecoveryPassword)
"@ | Out-File -FilePath $KeyFile -Encoding UTF8 -Force
    Write-Host ("Clave de recuperacion guardada en: {0}" -f $KeyFile) -ForegroundColor Green
} catch {
    Write-Host ("Error en BitLocker: {0}" -f $_.Exception.Message) -ForegroundColor Red
}

# --- Fin ---
Write-Host ""
Write-Host "Configuracion completada. Reinicia para iniciar el cifrado de BitLocker en segundo plano." -ForegroundColor Green

try { Stop-Transcript | Out-Null } catch {}
Read-Host "Pulsa ENTER para cerrar esta ventana..."
