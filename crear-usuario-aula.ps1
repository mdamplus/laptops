# =========================================
# Script: Crear usuario Aula + Fondo de pantalla desde GitHub
# =========================================

$ErrorActionPreference = "Stop"

# --- 1) Crear usuario Aula sin contraseña ---
$AulaUser = "Aula"

try {
    if (Get-LocalUser -Name $AulaUser -ErrorAction SilentlyContinue) {
        Write-Host "El usuario '$AulaUser' ya existe. Actualizando propiedades..." -ForegroundColor Yellow
        Set-LocalUser -Name $AulaUser -Password $null -PasswordNeverExpires $true
    } else {
        # Crear usuario sin contraseña
        New-LocalUser -Name $AulaUser -NoPassword -FullName "Usuario Aula" -Description "Cuenta estándar para alumnos" -PasswordNeverExpires $true | Out-Null
    }

    # Asegurar que NO sea administrador
    try { Remove-LocalGroupMember -Group "Administrators" -Member $AulaUser -ErrorAction SilentlyContinue } catch {}
    try { Add-LocalGroupMember -Group "Users" -Member $AulaUser -ErrorAction SilentlyContinue } catch {}

    Write-Host "✓ Usuario 'Aula' creado/actualizado como estándar (sin contraseña)." -ForegroundColor Green
} catch {
    Write-Host "❌ Error creando/ajustando usuario: $($_.Exception.Message)" -ForegroundColor Red
}

# --- 2) Descargar e instalar fondo de pantalla por defecto ---
# URL en GitHub (usa el raw link para descargar directamente el archivo)
$WallpaperUrl  = "https://raw.githubusercontent.com/mdamplus/laptops/Wordpress/wallpaper-001.jpg"
$WallpaperDest = "C:\Windows\Web\Wallpaper\wallpaper-001.jpg"

try {
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $WallpaperDest -UseBasicParsing
    Write-Host "Imagen descargada en: $WallpaperDest" -ForegroundColor Green

    # Cambiar fondo para todos los usuarios nuevos mediante el registro por defecto
    $RegPath = "HKU\.DEFAULT\Control Panel\Desktop"
    Set-ItemProperty -Path $RegPath -Name Wallpaper -Value $WallpaperDest

    # Cambiar fondo para el usuario actual (Admin que ejecuta el script)
    $RegPathCurrent = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $RegPathCurrent -Name Wallpaper -Value $WallpaperDest
    rundll32.exe user32.dll, UpdatePerUserSystemParameters

    Write-Host "✓ Fondo de pantalla establecido como predeterminado." -ForegroundColor Green
} catch {
    Write-Host "❌ Error configurando fondo de pantalla: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "✅ Configuración completada. El usuario Aula no tiene contraseña y es cuenta estándar." -ForegroundColor Green
Read-Host "Pulsa ENTER para cerrar esta ventana..."
