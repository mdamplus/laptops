# Prep-Master.ps1
# Ejecutar en Modo Auditoría (Ctrl+Shift+F3)

# --- Ajustes generales / políticas para evitar líos con Sysprep ---
# Desactivar Consumer Experience y contenidos sugeridos
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name DisableConsumerAccountStateContent -Type DWord -Value 1
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name DisableSoftLanding -Type DWord -Value 1
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name DisableWindowsSpotlightFeatures -Type DWord -Value 1

# Desactivar actualizaciones automáticas de Microsoft Store y UWP
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name AutoDownload -Type DWord -Value 2    # 2 = deshabilitar
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name DisableStoreApps -Type DWord -Value 1

# Desactivar tareas de actualizaciones en segundo plano (App Installer / Clipchamp, etc.)
$tasks = @(
  "\Microsoft\Windows\AppxDeploymentClient\Pre-staged app cleanup",
  "\Microsoft\Windows\Clip\License Validation",
  "\Microsoft\Windows\PushToInstall\LoginCheck"
)
foreach($t in $tasks){ try { Disable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } catch {} }

# --- Quitar apps modernas provisionadas que suelen romper Sysprep ---
# (Lista conservadora: Xbox, Clipchamp, News, Weather, GetHelp, Tips, 3DViewer, etc.)
$remove = @(
  "Microsoft.549981C3F5F10",            # Cortana (legacy)
  "Microsoft.SkypeApp",
  "Microsoft.XboxApp","Microsoft.Xbox.TCUI","Microsoft.XboxGamingOverlay","Microsoft.GamingApp",
  "Microsoft.ZuneMusic","Microsoft.ZuneVideo",  # Groove/Movies&TV
  "Microsoft.BingNews","Microsoft.BingWeather",
  "Microsoft.GetHelp","Microsoft.Getstarted","Microsoft.Tips",
  "Microsoft.Microsoft3DViewer","Microsoft.Paint3D",
  "Microsoft.MicrosoftOfficeHub",
  "MicrosoftWindows.Client.WebExperience", # Widgets/News feed
  "Clipchamp.Clipchamp",
  "MicrosoftTeams" # UWP antigua si existiera
)

# Quitar para el usuario actual
Get-AppxPackage | Where-Object { $remove -contains $_.Name } | Remove-AppxPackage -ErrorAction SilentlyContinue
# Quitar provisionado (para nuevos usuarios)
Get-AppxProvisionedPackage -Online | Where-Object { $remove -contains $_.DisplayName } | ForEach-Object {
  Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
}

# --- Instalar aplicaciones con winget ---
# Asegura que winget está disponible en la imagen (Windows 10 21H2+ / Windows 11)
$apps = @(
  @{ id="Google.Chrome";                 name="Google Chrome" },
  @{ id="Microsoft.Teams";               name="Microsoft Teams" },     # new Teams
  @{ id="Zoom.Zoom";                     name="Zoom" },
  @{ id="Nomic-AI.GPT4All";              name="GPT4All" },             # si no existe, ver notas
  @{ id="Bitdefender.Bitdefender";       name="Bitdefender" }          # ver notas sobre edición/empresa
)

foreach($app in $apps){
  try{
    winget install --id $($app.id) --silent --accept-package-agreements --accept-source-agreements
  } catch {
    Write-Host "No se pudo instalar via winget: $($app.name). Revisa el ID o instala manualmente."
  }
}

# --- Fondo de escritorio global por defecto ---
$wallDir = "C:\Windows\Web\Wallpaper\Arrabal"
$wallFile = Join-Path $wallDir "arrabal.jpg"   # coloca tu imagen con este nombre
New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
# Si ya tienes la imagen en otra ruta, cópiala aquí. Ejemplo (descomenta y ajusta):
# Copy-Item "C:\Temp\miFondo.jpg" $wallFile -Force

# Forzar fondo para todos los usuarios (política del sistema)
New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Force | Out-Null
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name Wallpaper -Type String -Value $wallFile
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name WallpaperStyle -Type String -Value "2"  # 2 = Ajustar (Fill)

# También establecer en perfil Default (nuevo usuario)
$defHive = "HKU\DEFAULT"
reg load $defHive "C:\Users\Default\NTUSER.DAT" | Out-Null
Set-ItemProperty "Registry::$defHive\Control Panel\Desktop" -Name Wallpaper -Value $wallFile -Type String
Set-ItemProperty "Registry::$defHive\Control Panel\Desktop" -Name WallpaperStyle -Value "2" -Type String
reg unload $defHive | Out-Null

# --- Perfil Wi-Fi para todos los usuarios ---
$wifiName = "Asociación Arrabal Alumnos"
$wifiKey  = "AsocArrb41!Alu"
$wifiXml  = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$wifiName</name>
  <SSIDConfig>
    <SSID>
      <name>$wifiName</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>$wifiKey</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>
"@
$wifiXmlPath = "C:\Unattend\wifi.xml"
New-Item -ItemType Directory -Path (Split-Path $wifiXmlPath) -Force | Out-Null
$wifiXml | Out-File -FilePath $wifiXmlPath -Encoding ASCII -Force
netsh wlan add profile filename="$wifiXmlPath" user=all | Out-Null

# --- Cuentas locales: Admin y Alumnado ---
# Si ya existen, no pasa nada. Ajusta contraseña si lo necesitas.
function Ensure-LocalUser {
  param($User,$Pwd,$IsAdmin=$false)
  if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
    $sec = ConvertTo-SecureString $Pwd -AsPlainText -Force
    New-LocalUser -Name $User -Password $sec -PasswordNeverExpires:$true -UserMayNotChangePassword:$true
    if($IsAdmin){ Add-LocalGroupMember -Group "Administrators" -Member $User }
  } else {
    if($IsAdmin){ Add-LocalGroupMember -Group "Administrators" -Member $User -ErrorAction SilentlyContinue }
  }
}

# EJEMPLOS (descomenta y define contraseñas si quieres que el script las cree/ajuste):
# Ensure-LocalUser -User "Admin" -Pwd "CambiaEsta#2025" -IsAdmin $true
# Ensure-LocalUser -User "Alumnado" -Pwd "Alumno#2025" -IsAdmin $false

Write-Host "Preparación completada. Revisa que el fondo exista en $wallFile y que winget instaló todo."
