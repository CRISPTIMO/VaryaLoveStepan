#!/usr/bin/env bash
# Сборка APK без Gradle: нужны только android.jar (platform 37) и build-tools 37.
# Запуск из Git Bash:  bash android/build-apk.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DL="$HERE/../sdk-download"
TOOLS="$DL/tools"
OUT="$HERE/build-manual"
APP="$HERE/app/src/main"
PKG="com.varya.mentions"
JAR="/c/Program Files/Java/jdk-21.0.12/bin/jar.exe"

# распаковать скачанные архивы, если ещё не распакованы
if [ ! -d "$TOOLS" ]; then
  mkdir -p "$TOOLS"
  unzip -q "$DL/platform-37.0_r02.zip" -d "$TOOLS/platform"
  unzip -q "$DL/build-tools_r37_windows.zip" -d "$TOOLS/build-tools"
fi
ANDROID_JAR="$(find "$TOOLS/platform" -name android.jar | head -1)"
BT="$(dirname "$(find "$TOOLS/build-tools" -name 'aapt2*' | head -1)")"

rm -rf "$OUT" && mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

# свежая копия страницы
cp "$HERE/../index.html" "$APP/assets/index.html"

# манифест с package (у Gradle это namespace)
sed "s|<manifest |<manifest package=\"$PKG\" |" "$APP/AndroidManifest.xml" > "$OUT/AndroidManifest.xml"

# Windows-пути для инструментов SDK (cygpath -m = Windows с /, без проблем с escape)
W_ANDROID_JAR="$(cygpath -m "$ANDROID_JAR")"
W_OUT="$(cygpath -m "$OUT")"
W_APP="$(cygpath -m "$APP")"

echo "→ ресурсы"
"$BT/aapt2" compile --dir "$W_APP/res" -o "$W_OUT/res.zip"
"$BT/aapt2" link -I "$W_ANDROID_JAR" \
  --manifest "$W_OUT/AndroidManifest.xml" \
  --min-sdk-version 33 --target-sdk-version 37 \
  --version-code 1 --version-name 1.0 \
  -A "$W_APP/assets" --java "$W_OUT/gen" \
  -o "$W_OUT/unsigned.apk" "$W_OUT/res.zip"

echo "→ java"
# javac — Windows-exe; cygpath -m даёт пути с / (без escape-проблем)
find "$APP/java" "$OUT/gen" -name '*.java' \
  | while IFS= read -r f; do printf '"%s"\n' "$(cygpath -m "$f")"; done \
  > "$OUT/sources.txt"
javac --release 17 -encoding UTF-8 \
  -classpath "$W_ANDROID_JAR" \
  -d "$W_OUT/classes" \
  @"$W_OUT/sources.txt"

echo "→ dex"
mapfile -t CLASS_FILES < <(find "$OUT/classes" -name '*.class' \
  | while IFS= read -r f; do cygpath -m "$f"; done)
# Пишем вызов d8 во временный .bat, чтобы не воевать с кавычками cmd /c
D8_BAT="$OUT/run_d8.bat"
{
  printf '@echo off\n'
  printf 'call "%s" --release --min-api 33 --lib "%s" --output "%s"' \
    "$(cygpath -w "$BT/d8.bat")" "$W_ANDROID_JAR" "$W_OUT/dex"
  for f in "${CLASS_FILES[@]}"; do printf ' "%s"' "$f"; done
  printf '\n'
} > "$D8_BAT"
cmd /c "$(cygpath -w "$D8_BAT")"
(cd "$OUT/dex" && "$JAR" -uMf "$(cygpath -m "$OUT/unsigned.apk")" classes.dex)

echo "→ подпись"
KS="$HERE/release.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -keystore "$(cygpath -m "$KS")" -alias mentions -keyalg RSA -keysize 2048 \
    -validity 36500 -storepass mentions -keypass mentions -dname "CN=Mentions" >/dev/null
fi
W_ALIGNED="$(cygpath -m "$OUT/aligned.apk")"
W_FINAL="$(cygpath -m "$HERE/../Schetchik.apk")"
"$BT/zipalign.exe" -f -p 4 "$W_OUT/unsigned.apk" "$W_ALIGNED"
SIGN_BAT="$OUT/run_sign.bat"
{
  printf '@echo off\n'
  printf 'call "%s" sign --ks "%s" --ks-pass pass:mentions --key-pass pass:mentions --out "%s" "%s"\n' \
    "$(cygpath -w "$BT/apksigner.bat")" "$(cygpath -w "$KS")" "$W_FINAL" "$W_ALIGNED"
} > "$SIGN_BAT"
cmd /c "$(cygpath -w "$SIGN_BAT")"

echo "✓ готово: $HERE/../Schetchik.apk"
