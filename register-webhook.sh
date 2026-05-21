#!/bin/bash
# register-webhook.sh SESSION_ID
# Registra el webhook de n8n en OpenWA

set -e

SESSION_ID=$1
API_KEY=$(cat ./data/openwa/.api-key 2>/dev/null || true)

if [ -z "$SESSION_ID" ]; then
  echo "Uso: bash register-webhook.sh SESSION_ID"
  echo "Ejemplo: bash register-webhook.sh mi-bot"
  exit 1
fi

if [ -z "$API_KEY" ]; then
  echo "ERROR: No se encontró .api-key en data/openwa/"
  echo "Asegúrate de que OpenWA haya arrancado correctamente."
  exit 1
fi

echo "Registrando webhook para sesión: $SESSION_ID"

curl -s -X POST "http://localhost:2785/api/sessions/$SESSION_ID/webhooks" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "url": "http://n8n:5678/webhook/payload",
    "events": ["message.received"]
  }'

echo ""
echo "=============================================="
echo " Webhook registrado correctamente"
echo "=============================================="
echo ""
echo "Actualiza tu .env con estos valores:"
echo "  OPENWA_SESSION_ID=$SESSION_ID"
echo "  OPENWA_API_KEY=$API_KEY"
echo ""
echo "Luego reinicia n8n para aplicar las variables:"
echo "  docker compose restart n8n"
echo ""
