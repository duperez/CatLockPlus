#!/bin/bash
# Compila o CatLockPlus e monta o .app
# Uso: bash build.sh
set -e
cd "$(dirname "$0")"

if ! command -v swiftc &>/dev/null; then
  echo "swiftc não encontrado. Instale as ferramentas de linha de comando com:"
  echo "  xcode-select --install"
  exit 1
fi

APP="CatLockPlus.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Binário universal: compila para Apple Silicon e Intel, depois junta com lipo
for ARCH in arm64 x86_64; do
  echo "Compilando para $ARCH..."
  swiftc main.swift -O \
    -target "${ARCH}-apple-macos11" \
    -o "CatLockPlus-${ARCH}" \
    -framework AppKit \
    -F /System/Library/PrivateFrameworks \
    -framework DFRFoundation
done
lipo -create -output "$APP/Contents/MacOS/CatLockPlus" CatLockPlus-arm64 CatLockPlus-x86_64
rm -f CatLockPlus-arm64 CatLockPlus-x86_64
echo "Arquiteturas: $(lipo -archs "$APP/Contents/MacOS/CatLockPlus")"

cp Info.plist "$APP/Contents/Info.plist"
# Remove atributos estendidos do Finder que impedem a assinatura
xattr -cr "$APP"

# Usa certificado estável se existir (mantém a permissão de Acessibilidade entre builds)
if security find-identity -p codesigning -v 2>/dev/null | grep -q "CatLockPlusCert"; then
  echo "Assinando com CatLockPlusCert (permissão de Acessibilidade persiste)"
  codesign --force --sign "CatLockPlusCert" "$APP"
else
  echo "⚠️  Assinatura ad-hoc: a permissão de Acessibilidade será pedida de novo a cada build."
  echo "   Veja no README como criar o certificado CatLockPlusCert para evitar isso."
  codesign --force --sign - "$APP"
fi

echo ""
echo "✅ Pronto! Para abrir:  open $APP"
echo "Dica: mova o app para /Applications se quiser mantê-lo:"
echo "  mv $APP /Applications/"
