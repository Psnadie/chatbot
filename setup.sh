#!/bin/bash
# setup.sh — ejecutar UNA VEZ después del primer docker compose up

set -e

echo "Esperando que OpenWA esté listo..."
until curl -sf http://localhost:2785/api/health > /dev/null 2>&1; do
  sleep 3
done

echo "OpenWA listo."

# Leer API key generada automáticamente
API_KEY=$(cat ./data/openwa/.api-key 2>/dev/null || true)
if [ -z "$API_KEY" ]; then
  echo "ERROR: No se encontró .api-key en data/openwa/"
  echo "Asegúrate de que OpenWA haya arrancado completamente y revisa los logs con: docker compose logs openwa"
  exit 1
fi

echo ""
echo "=============================================="
echo " API Key detectada: $API_KEY"
echo "=============================================="
echo ""
echo "=== PASOS MANUALES ==="
echo "1. Abre http://localhost:2886 en tu navegador"
echo "2. Crea una sesión nueva (nombre sugerido: mi-bot)"
echo "3. Inicia la sesión y escanea el QR con WhatsApp"
echo "4. Cuando la sesión esté activa, ejecuta:"
echo "   bash register-webhook.sh SESSION_ID"
echo ""
echo "Guarda esta API Key en tu .env como:"
echo "  OPENWA_API_KEY=$API_KEY"
echo ""
