$ErrorActionPreference = "Stop"

$Root     = Split-Path $PSScriptRoot -Parent
$Here     = $PSScriptRoot
$DL       = Join-Path $Root "sdk-download\tools"
$Out      = Join-Path $Here "build-manual"
$App      = Join-Path $Here "app\src\main"
$Pkg      = "com.varya.mentions"
$JavaHome = "C:\Program Files\Java\jdk-21.0.12"

# --- Найти инструменты -------------------------------------------------------
$PlatformDir = Get-ChildItem "$DL\platform" -Recurse -Filter "android.jar" |
               Select-Object -First 1 -ExpandProperty DirectoryName
$AndroidJar  = Join-Path $PlatformDir "android.jar"

$BtDir = Get-ChildItem "$DL\build-tools" -Recurse -Filter "aapt2.exe" |
         Select-Object -First 1 -ExpandProperty DirectoryName

$Aapt2     = Join-Path $BtDir "aapt2.exe"
$D8Bat     = Join-Path $BtDir "d8.bat"
$ZipAlign  = Join-Path $BtDir "zipalign.exe"
$Apksigner = Join-Path $BtDir "apksigner.bat"
$Javac     = Join-Path $JavaHome "bin\javac.exe"
$Jar       = Join-Path $JavaHome "bin\jar.exe"
$Keytool   = Join-Path $JavaHome "bin\keytool.exe"

# --- Подготовка ---------------------------------------------------------------
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item "$Out\gen", "$Out\classes", "$Out\dex" -ItemType Directory | Out-Null

# Свежая копия HTML
Copy-Item "$Root\index.html" "$App\assets\index.html" -Force

# Манифест с package=""
$PkgAttr = 'package="' + $Pkg + '" '
(Get-Content "$App\AndroidManifest.xml" -Raw) `
    -replace '<manifest ', ('<manifest ' + $PkgAttr) |
    Set-Content "$Out\AndroidManifest.xml" -Encoding UTF8

# --- Ресурсы ------------------------------------------------------------------
Write-Host "→ ресурсы"
& $Aapt2 compile --dir "$App\res" -o "$Out\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile failed" }

& $Aapt2 link -I $AndroidJar `
    --manifest "$Out\AndroidManifest.xml" `
    --min-sdk-version 33 --target-sdk-version 37 `
    --version-code 1 --version-name "1.0" `
    -A "$App\assets" --java "$Out\gen" `
    -o "$Out\unsigned.apk" "$Out\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

# --- Java → .class -----------------------------------------------------------
Write-Host "→ java"
$JavaFiles = Get-ChildItem "$App\java","$Out\gen" -Recurse -Filter "*.java" |
             Select-Object -ExpandProperty FullName
$SrcFile = "$Out\sources.txt"
# Пишем без BOM — javac 21 не любит BOM в @argfile
$Lines = $JavaFiles | ForEach-Object { "`"$($_.Replace('\','/'))`"" }
[System.IO.File]::WriteAllLines($SrcFile, $Lines, [System.Text.UTF8Encoding]::new($false))

& $Javac --release 17 -encoding UTF-8 -classpath $AndroidJar -d "$Out\classes" "@$SrcFile"
if ($LASTEXITCODE -ne 0) { throw "javac failed" }

# --- .class → .dex -----------------------------------------------------------
Write-Host "-> dex"
$ClassFiles = Get-ChildItem "$Out\classes" -Recurse -Filter "*.class" |
              Select-Object -ExpandProperty FullName

# Пишем temp bat для d8, чтобы не воевать с кавычками cmd /c
$D8RunBat = "$Out\run_d8.bat"
$D8Args = ($ClassFiles | ForEach-Object { "`"$_`"" }) -join " "
"@echo off" | Set-Content $D8RunBat -Encoding ASCII
"call `"$D8Bat`" --release --min-api 33 --lib `"$AndroidJar`" --output `"$Out\dex`" $D8Args" |
    Add-Content $D8RunBat -Encoding ASCII
$p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$D8RunBat`"" -Wait -PassThru -NoNewWindow
if ($p.ExitCode -ne 0) { throw "d8 failed" }

# Вставить classes.dex в APK
Push-Location "$Out\dex"
& $Jar -uMf "$Out\unsigned.apk" classes.dex
if ($LASTEXITCODE -ne 0) { throw "jar update failed" }
Pop-Location

# --- Подпись ------------------------------------------------------------------
Write-Host "→ подпись"
$KS = Join-Path $Here "release.keystore"
if (-not (Test-Path $KS)) {
    & $Keytool -genkeypair -keystore $KS -alias mentions -keyalg RSA -keysize 2048 `
        -validity 36500 -storepass mentions -keypass mentions -dname "CN=Mentions" | Out-Null
}

$Final = Join-Path $Root "Schetchik.apk"
& $ZipAlign -f -p 4 "$Out\unsigned.apk" "$Out\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

$SignBat = "$Out\run_sign.bat"
"@echo off" | Set-Content $SignBat -Encoding ASCII
"call `"$Apksigner`" sign --ks `"$KS`" --ks-pass pass:mentions --key-pass pass:mentions --out `"$Final`" `"$Out\aligned.apk`"" |
    Add-Content $SignBat -Encoding ASCII
$p2 = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$SignBat`"" -Wait -PassThru -NoNewWindow
if ($p2.ExitCode -ne 0) { throw "apksigner failed" }

Write-Host "Done: $Final"
