# =============================================================================
#  build_release.ps1 — Setup + Build de release para Google Play
#  Uso: coloca este archivo en la raiz de cualquier proyecto Flutter y ejecuta:
#       .\build_release.ps1
#
#  Primera ejecucion: genera keystore y key.properties automaticamente.
#  Ejecuciones posteriores: detecta la configuracion existente y compila.
# =============================================================================

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

# ---------------------------------------------------------------------------
# Colores helpers
# ---------------------------------------------------------------------------
function Write-Step  { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "   [OK] $msg" -ForegroundColor Green }
function Write-Fail  { param($msg) Write-Host "   [ERROR] $msg" -ForegroundColor Red }
function Write-Warn  { param($msg) Write-Host "   [AVISO] $msg" -ForegroundColor Yellow }
function Write-Info  { param($msg) Write-Host "   $msg" -ForegroundColor Gray }

# ---------------------------------------------------------------------------
# Rutas fijas relativas al proyecto
# ---------------------------------------------------------------------------
$KeystoreFile     = "$ProjectRoot\android\upload-keystore.jks"
$KeyPropertiesFile = "$ProjectRoot\android\key.properties"
$AabOutput        = "$ProjectRoot\build\app\outputs\bundle\release\app-release.aab"
$ApkOutput        = "$ProjectRoot\build\app\outputs\flutter-apk\app-release.apk"

# Busca keytool: Android Studio → JAVA_HOME → PATH
$KeytoolExe = @(
    "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe",
    "$env:JAVA_HOME\bin\keytool.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $KeytoolExe) {
    $found = Get-Command keytool -ErrorAction SilentlyContinue
    if ($found) { $KeytoolExe = $found.Source }
}

# ===========================================================================
# 1. Verificar prerequisitos basicos
# ===========================================================================
Write-Step "Verificando prerequisitos..."

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Fail "Flutter no encontrado en el PATH. Instala Flutter y vuelve a intentarlo."
    exit 1
}
Write-Ok "Flutter detectado"

if (-not (Test-Path "$ProjectRoot\pubspec.yaml")) {
    Write-Fail "pubspec.yaml no encontrado. Ejecuta el script desde la raiz del proyecto Flutter."
    exit 1
}
Write-Ok "Proyecto Flutter detectado"

if (-not $KeytoolExe) {
    Write-Fail "keytool no encontrado. Instala el JDK o Android Studio."
    exit 1
}
Write-Ok "keytool encontrado en: $KeytoolExe"

# ===========================================================================
# 2. Leer nombre y version del proyecto desde pubspec.yaml
# ===========================================================================
Write-Step "Leyendo pubspec.yaml..."

$pubspec = Get-Content "$ProjectRoot\pubspec.yaml" -Raw
if ($pubspec -match 'version:\s+(\d+\.\d+\.\d+)\+(\d+)') {
    $VersionName = $Matches[1]
    $VersionCode = [int]$Matches[2]
    Write-Ok "Version: $VersionName (build $VersionCode)"
} else {
    Write-Fail "No se pudo leer la version del pubspec.yaml. Formato esperado: version: 1.0.0+1"
    exit 1
}
$AppName = if ($pubspec -match '(?m)^name:\s+(\S+)') { $Matches[1] } else { "app" }
Write-Ok "App: $AppName"

# ===========================================================================
# 3. SETUP: Crear keystore y key.properties si no existen
# ===========================================================================
$needsSetup = (-not (Test-Path $KeystoreFile)) -or (-not (Test-Path $KeyPropertiesFile))

if ($needsSetup) {
    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host "  PRIMER USO — Configuracion de firma de release" -ForegroundColor Yellow
    Write-Host "  Se creara el keystore y key.properties para este proyecto." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow

    # --- Datos del certificado ---
    Write-Host ""
    Write-Info "Completa los datos para el certificado (puedes dejar algunos vacios):"

    $certCN = Read-Host "   Nombre o empresa (CN)"
    if (-not $certCN) { $certCN = $AppName }

    $certOU = Read-Host "   Departamento (OU) [opcional]"
    if (-not $certOU) { $certOU = "Dev" }

    $certO  = Read-Host "   Organizacion (O) [opcional]"
    if (-not $certO)  { $certO  = $certCN }

    $certL  = Read-Host "   Ciudad (L) [opcional]"
    if (-not $certL)  { $certL  = "Ciudad" }

    $certST = Read-Host "   Provincia/Estado (ST) [opcional]"
    if (-not $certST) { $certST = "Provincia" }

    $certC  = Read-Host "   Pais, 2 letras (C) [AR]"
    if (-not $certC)  { $certC  = "AR" }

    $dname = "CN=$certCN, OU=$certOU, O=$certO, L=$certL, ST=$certST, C=$certC"

    # --- Contrasenas ---
    Write-Host ""
    Write-Info "Define las contrasenas del keystore (minimo 6 caracteres):"

    do {
        $storePassRaw = Read-Host "   Contrasena del keystore" -AsSecureString
        $storePass    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($storePassRaw))
        if ($storePass.Length -lt 6) { Write-Warn "Debe tener al menos 6 caracteres." }
    } while ($storePass.Length -lt 6)

    $samePass = Read-Host "   Usar la misma contrasena para la clave? [S/n]"
    if ($samePass.ToLower() -eq "n") {
        do {
            $keyPassRaw = Read-Host "   Contrasena de la clave" -AsSecureString
            $keyPass    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                              [Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyPassRaw))
            if ($keyPass.Length -lt 6) { Write-Warn "Debe tener al menos 6 caracteres." }
        } while ($keyPass.Length -lt 6)
    } else {
        $keyPass = $storePass
    }

    $keyAlias = Read-Host "   Alias de la clave [upload]"
    if (-not $keyAlias) { $keyAlias = "upload" }

    # --- Generar keystore ---
    Write-Step "Generando keystore..."
    & $KeytoolExe -genkey -v `
        -keystore $KeystoreFile `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -alias $keyAlias `
        -dname $dname `
        -storepass $storePass `
        -keypass $keyPass

    if (-not (Test-Path $KeystoreFile)) {
        Write-Fail "No se pudo generar el keystore."
        exit 1
    }
    Write-Ok "Keystore generado: $KeystoreFile"

    # --- Crear key.properties ---
    Write-Step "Creando android\key.properties..."
    @"
storePassword=$storePass
keyPassword=$keyPass
keyAlias=$keyAlias
storeFile=../upload-keystore.jks
"@ | Set-Content $KeyPropertiesFile -Encoding UTF8
    Write-Ok "key.properties creado"

    # --- Asegurar que key.properties y *.jks esten en .gitignore ---
    $gitignorePath = "$ProjectRoot\android\.gitignore"
    if (Test-Path $gitignorePath) {
        $gi = Get-Content $gitignorePath -Raw
        $changed = $false
        if ($gi -notmatch 'key\.properties') {
            Add-Content $gitignorePath "`nkey.properties"
            $changed = $true
        }
        if ($gi -notmatch '\*\*\/\*\.jks') {
            Add-Content $gitignorePath "`n**/*.jks"
            $changed = $true
        }
        if ($changed) { Write-Ok ".gitignore actualizado (keystore y key.properties excluidos)" }
    }

    # --- Verificar/actualizar build.gradle.kts para firma release ---
    Write-Step "Verificando configuracion de firma en build.gradle.kts..."
    $gradlePath = "$ProjectRoot\android\app\build.gradle.kts"
    if (Test-Path $gradlePath) {
        $gradle = Get-Content $gradlePath -Raw
        if ($gradle -match 'signingConfigs\.getByName\("debug"\)') {
            Write-Warn "build.gradle.kts usa firma debug. Actualizando a release..."

            # Agrega imports si no existen
            if ($gradle -notmatch 'import java\.util\.Properties') {
                $gradle = "import java.util.Properties`nimport java.io.FileInputStream`n`n" + $gradle
            }

            # Agrega bloque de lectura de key.properties antes de android {
            if ($gradle -notmatch 'keystorePropertiesFile') {
                $gradle = $gradle -replace '(android\s*\{)', @"
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

`$1
"@
            }

            # Agrega signingConfigs release antes de buildTypes
            if ($gradle -notmatch 'signingConfigs\s*\{') {
                $gradle = $gradle -replace '(\s*buildTypes\s*\{)', @"

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
`$1
"@
            }

            # Reemplaza signingConfig debug por release dentro de buildTypes release
            $gradle = $gradle -replace 'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                                       'signingConfig = signingConfigs.getByName("release")'

            Set-Content $gradlePath $gradle -Encoding UTF8
            Write-Ok "build.gradle.kts actualizado con firma release"
        } else {
            Write-Ok "build.gradle.kts ya tiene firma release configurada"
        }
    } else {
        Write-Warn "No se encontro build.gradle.kts. Configura la firma manualmente."
    }

    Write-Host ""
    Write-Host "  IMPORTANTE: Haz una copia de seguridad de estos archivos." -ForegroundColor Red
    Write-Host "  Si los pierdes, no podras actualizar la app en Google Play." -ForegroundColor Red
    Write-Host "  - $KeystoreFile" -ForegroundColor Red
    Write-Host "  - $KeyPropertiesFile" -ForegroundColor Red
    Write-Host ""
    Read-Host "  Presiona Enter para continuar con el build..."

} else {
    Write-Ok "Keystore y key.properties encontrados. Continuando con el build."

    # Leer alias desde key.properties para usarlo en la verificacion
    $kp = Get-Content $KeyPropertiesFile -Raw
    $keyAlias = if ($kp -match 'keyAlias\s*=\s*(.+)') { $Matches[1].Trim() } else { "upload" }
}

# ===========================================================================
# 4. Incrementar version (opcional)
# ===========================================================================
Write-Step "Gestion de version..."
$bump = Read-Host "   Incrementar version? [s=patch / m=minor / N=ninguno] (Enter = ninguno)"

switch ($bump.ToLower()) {
    "s" {
        $parts = $VersionName.Split('.')
        $parts[2] = [string]([int]$parts[2] + 1)
        $VersionName = $parts -join '.'
        $VersionCode++
        $pubspec = $pubspec -replace 'version:\s+\d+\.\d+\.\d+\+\d+', "version: $VersionName+$VersionCode"
        Set-Content "$ProjectRoot\pubspec.yaml" $pubspec -Encoding UTF8
        Write-Ok "Version actualizada a: $VersionName+$VersionCode"
    }
    "m" {
        $parts = $VersionName.Split('.')
        $parts[1] = [string]([int]$parts[1] + 1)
        $parts[2] = "0"
        $VersionName = $parts -join '.'
        $VersionCode++
        $pubspec = $pubspec -replace 'version:\s+\d+\.\d+\.\d+\+\d+', "version: $VersionName+$VersionCode"
        Set-Content "$ProjectRoot\pubspec.yaml" $pubspec -Encoding UTF8
        Write-Ok "Version actualizada a: $VersionName+$VersionCode"
    }
    default {
        Write-Warn "Se mantiene la version: $VersionName+$VersionCode"
    }
}

# ===========================================================================
# 5. Limpiar build anterior
# ===========================================================================
Write-Step "Limpiando build anterior (flutter clean)..."
Set-Location $ProjectRoot
flutter clean
Write-Ok "Limpieza completada"

# ===========================================================================
# 6. Obtener dependencias
# ===========================================================================
Write-Step "Obteniendo dependencias (flutter pub get)..."
flutter pub get
Write-Ok "Dependencias listas"

# ===========================================================================
# 7. Construir Android App Bundle (AAB) — recomendado para Google Play
# ===========================================================================
Write-Step "Construyendo Android App Bundle (.aab) en modo RELEASE..."
flutter build appbundle --release

if (-not (Test-Path $AabOutput)) {
    Write-Fail "No se genero el .aab en: $AabOutput"
    exit 1
}
$AabSize = [math]::Round((Get-Item $AabOutput).Length / 1MB, 2)
Write-Ok "AAB generado: $AabOutput ($AabSize MB)"

# ===========================================================================
# 8. (Opcional) Construir APK release
# ===========================================================================
$buildApk = Read-Host "`n   Tambien generar APK release? [s/N]"
if ($buildApk.ToLower() -eq "s") {
    Write-Step "Construyendo APK release..."
    flutter build apk --release
    if (Test-Path $ApkOutput) {
        $ApkSize = [math]::Round((Get-Item $ApkOutput).Length / 1MB, 2)
        Write-Ok "APK generado: $ApkOutput ($ApkSize MB)"
    } else {
        Write-Warn "No se encontro el APK en la ruta esperada."
    }
}

# ===========================================================================
# 9. Verificar firma del AAB
# ===========================================================================
Write-Step "Verificando firma del AAB..."
& $KeytoolExe -printcert -jarfile $AabOutput 2>&1 |
    Select-String "Owner|Emisor|Issuer|SHA|Valido|Valid" |
    ForEach-Object { Write-Ok $_.Line.Trim() }

# ===========================================================================
# 10. Copiar artefactos a releases\ con nombre versionado
# ===========================================================================
Write-Step "Copiando artefactos a releases\..."
$ReleasesDir = "$ProjectRoot\releases"
if (-not (Test-Path $ReleasesDir)) { New-Item -ItemType Directory -Path $ReleasesDir | Out-Null }

$AabDest = "$ReleasesDir\$AppName-$VersionName+$VersionCode.aab"
Copy-Item $AabOutput $AabDest -Force
Write-Ok "AAB copiado a: $AabDest"

if ($buildApk.ToLower() -eq "s" -and (Test-Path $ApkOutput)) {
    $ApkDest = "$ReleasesDir\$AppName-$VersionName+$VersionCode.apk"
    Copy-Item $ApkOutput $ApkDest -Force
    Write-Ok "APK copiado a: $ApkDest"
}

# ===========================================================================
# Resumen final
# ===========================================================================
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  BUILD COMPLETADO" -ForegroundColor Cyan
Write-Host "  App     : $AppName" -ForegroundColor White
Write-Host "  Version : $VersionName (versionCode $VersionCode)" -ForegroundColor White
Write-Host "  AAB     : $AabDest" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "`n  Sube el archivo .aab en Google Play Console:" -ForegroundColor Yellow
Write-Host "  https://play.google.com/console" -ForegroundColor Yellow
Write-Host ""
