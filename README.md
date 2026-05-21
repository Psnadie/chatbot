# WhatsApp Bot — OpenWA + n8n + Groq

Infraestructura Docker local que integra OpenWA (gateway WhatsApp HTTP API) con n8n (automatización de workflows) y Groq (LLM). Todo corre en una red Docker interna sin dependencias externas ni túneles.

## Arquitectura

```
                  ┌─────────────────────────────────────┐
                  │          Red: bot-network            │
                  │                                     │
                  │  ┌──────────┐     ┌──────────────┐  │
                  │  │  openwa  │     │     n8n      │  │
                  │  │ :2785    │────►│ :5678        │  │
                  │  │ :2886    │     │ /webhook/    │  │
                  │  │ (nginx)  │     │   payload    │  │
                  │  └────┬─────┘     └──────┬───────┘  │
                  │       │                  │          │
                  │       │                  │          │
                  │  POST /api/sessions/     │          │
                  │   :sessionId/messages/   │          │
                  │   send-text              │          │
                  └─────────────────────────────────────┘
                           │                         │
                    WhatsApp API              HTTP POST
                  (webhooks baas              (mensajes
                   recibidos)               entrantes)

Browser ─── localhost:2886 (dashboard OpenWA)
Browser ─── localhost:5678 (n8n editor)
API     ─── localhost:2785 (OpenWA REST API)
```

## Requisitos

- Docker y Docker Compose v2
- WSL2 (si estás en Windows)
- Una API key de [Groq](https://console.groq.com)
- Un número de WhatsApp (para escanear el QR)

## Estructura del proyecto

```
whatsapp-bot/
├── .env                        # Variables de entorno
├── docker-compose.yml          # Orquestación de servicios
├── Dockerfile.openwa           # Imagen de OpenWA + nginx
├── dashboard-nginx.conf        # Proxy inverso para dashboard
├── start-openwa.sh             # Script de arranque del contenedor
├── setup.sh                    # Script de inicialización post-arranque
├── register-webhook.sh         # Registro del webhook en OpenWA
├── n8n/
│   └── workflows/
│       └── ChatWhatsapp.json   # Workflow de n8n importable
└── data/
    ├── openwa/                 # Persistencia de sesiones WhatsApp
    └── n8n/                    # Persistencia de n8n
```

## Configuración del archivo .env

```env
OPENWA_SESSION_ID=c5d487b7-c4de-4bea-98a6-048263bb294a
OPENWA_API_KEY=dev-admin-key
GROQ_API_KEY=gsk_tu_api_key_aqui
N8N_ENCRYPTION_KEY=string_aleatorio_para_cifrado
```

| Variable | Descripción | Cómo obtenerla |
|---|---|---|
| `OPENWA_SESSION_ID` | ID de la sesión de WhatsApp en OpenWA | Se crea desde el dashboard (`localhost:2886`) o via API |
| `OPENWA_API_KEY` | Clave de API de OpenWA | Se genera automáticamente al arrancar OpenWA. Se lee de `data/openwa/.api-key` |
| `GROQ_API_KEY` | API key de Groq (para el modelo Llama 3.1 8B) | Consola de Groq: https://console.groq.com |
| `N8N_ENCRYPTION_KEY` | Clave de cifrado interno de n8n (credenciales, etc.) | Generar con: `openssl rand -hex 32` |

## Despliegue paso a paso

### 1. Preparar variables de entorno

```bash
cp .env.example .env   # si existe, o edita .env directamente
# Rellena GROQ_API_KEY y N8N_ENCRYPTION_KEY
# OPENWA_SESSION_ID y OPENWA_API_KEY se rellenan más tarde
```

### 2. Levantar los contenedores

```bash
docker compose up -d
```

Esto construye la imagen de OpenWA (clona el repo, instala dependencias, construye el dashboard y la API) y arranca ambos servicios. El primer build tarda varios minutos.

### 3. Ejecutar setup

```bash
bash setup.sh
```

El script espera a que OpenWA esté listo y muestra la API Key generada automáticamente.

### 4. Crear sesión de WhatsApp (manual)

1. Abre `http://localhost:2886` en el navegador
2. Inicia sesión con la API Key que aparece en `setup.sh`
3. Crea una sesión nueva (ej: `mi-bot`)
4. Inicia la sesión y escanea el código QR con WhatsApp
5. Espera a que la sesión aparezca como `CONNECTED`

### 5. Registrar el webhook

```bash
bash register-webhook.sh c5d487b7-c4de-4bea-98a6-048263bb294a
```

Sustituye `c5d487b7...` por el ID de sesión que creaste. Esto registra en OpenWA un webhook que envía los mensajes entrantes a `http://n8n:5678/webhook/payload`.

### 6. Actualizar .env y reiniciar n8n

```bash
# Edita .env con los valores del script
OPENWA_SESSION_ID=c5d487b7-c4de-4bea-98a6-048263bb294a
OPENWA_API_KEY=dev-admin-key

# Luego reinicia n8n para que tome las variables
docker compose restart n8n
```

### 7. Importar y activar el workflow en n8n

1. Abre `http://localhost:5678`
2. Crea cuenta o inicia sesión
3. Ve a **Workflows** → **Import from File**
4. Selecciona `n8n/workflows/ChatWhatsapp.json`
5. Configura la credencial de Groq (necesitarás pegar tu `GROQ_API_KEY`)
6. Activa el workflow con el toggle superior derecho

### 8. Probar

Envía un mensaje de WhatsApp al número conectado. El flujo es:

```
WhatsApp → OpenWA (webhook) → n8n (/webhook/payload)
  → filtro fromMe===false → AI Agent (Groq Llama 3.1)
  → HTTP Request a OpenWA POST /messages/send-text
  → Respond to Webhook → WhatsApp
```

Para ver logs:

```bash
docker compose logs n8n --tail=20
docker compose logs openwa --tail=20
```

## Puertos expuestos

| Puerto | Servicio | Uso |
|---|---|---|
| `2785` | OpenWA API | API REST de OpenWA. Swagger docs en `/api/docs` |
| `2886` | OpenWA Dashboard (nginx) | Panel web para gestionar sesiones |
| `5678` | n8n | Editor de workflows y webhook receptor |

## Rutas de API relevantes

### OpenWA (`localhost:2785`)

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/api/health` | Health check |
| `GET` | `/api/docs` | Documentación Swagger |
| `GET` | `/api/sessions` | Listar sesiones |
| `POST` | `/api/sessions` | Crear sesión |
| `POST` | `/api/sessions/:id/webhooks` | Registrar webhook |
| `GET` | `/api/sessions/:id/webhooks` | Listar webhooks |
| `POST` | `/api/sessions/:id/messages/send-text` | Enviar mensaje de texto |

### n8n (`localhost:5678`)

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/webhook/payload` | Webhook que recibe mensajes de OpenWA |

## Variables de entorno en n8n

El workflow importado usa `$env.NOMBRE_VARIABLE` para leer variables del entorno del contenedor n8n, definidas en `docker-compose.yml`:

- `$env.OPENWA_SESSION_ID` — ID de sesión para enviar respuestas
- `$env.OPENWA_API_KEY` — API Key para autenticar contra OpenWA

## Comunicación entre contenedores

Ambos servicios están en la red bridge `bot-network`. OpenWA se comunica con n8n mediante el nombre del contenedor:

- **OpenWA → n8n**: `http://n8n:5678/webhook/payload` (registrado como webhook)
- **n8n → OpenWA**: `http://openwa:2785/api/sessions/...` (en el nodo HTTP Request)

No uses `localhost` ni `host.docker.internal` para comunicación entre contenedores del mismo `docker-compose.yml`.

## Detalles técnicos

### Dockerfile.openwa

- Basado en `node:20-alpine`
- Incluye Chromium para Puppeteer (necesario para WhatsApp Web)
- Instala y construye el dashboard de OpenWA
- Incluye nginx como proxy inverso para el dashboard
- Parchea la validación `@IsUrl({ require_tld: false })` para aceptar nombres de contenedor Docker como URLs de webhook

### dashboard-nginx.conf

Nginx escucha en puerto 2886 y:
- Sirve los archivos estáticos del dashboard (`/app/dashboard/dist`)
- Proxy inverso `/api/*` → `localhost:2785`
- Proxy inverso `/socket.io/*` → `localhost:2785`

### start-openwa.sh

Arranca nginx en background y la API de NestJS en foreground para mantener el contenedor vivo.

### Workflow de n8n (ChatWhatsapp.json)

Flujo:
1. **Webhook** — Recibe POST en `/webhook/payload`
2. **IF** — Filtra mensajes `fromMe === false` (ignora mensajes enviados por el propio bot)
3. **AI Agent** — Agente conversacional con Groq (Llama 3.1 8B)
4. **HTTP Request** — Envía la respuesta a OpenWA via `POST /messages/send-text`
5. **Respond to Webhook** — Responde `{ status: "ok" }` a OpenWA

## Troubleshooting

### "url must be a URL address" al registrar webhook

El decorador `@IsUrl()` de `class-validator` exige un TLD (`.com`) por defecto. El Dockerfile parchea automáticamente esta validación. Si ya tienes el contenedor corriendo sin el parche:

```bash
docker exec openwa sed -i 's/(0, class_validator_1.IsUrl)()/(0, class_validator_1.IsUrl)({ require_tld: false })/g' /app/dist/modules/webhook/dto/webhook.dto.js
docker compose restart openwa
```

### La sesión de WhatsApp se desconecta

Las sesiones persisten en `data/openwa/sessions/`. Si el contenedor se reconstruye sin el volumen, perderás la sesión. Asegúrate de que `docker-compose.yml` tenga el volumen mapeado:

```yaml
volumes:
  - ./data/openwa:/app/data
```

### n8n no responde al webhook

1. Verifica que el workflow esté activo (toggle verde en n8n)
2. Verifica que el webhook esté registrado:
   ```bash
   curl localhost:2785/api/sessions/TU_SESSION_ID/webhooks -H "X-API-Key: TU_API_KEY"
   ```
3. Revisa los logs: `docker compose logs n8n`

### El agente IA no responde

1. Verifica que `GROQ_API_KEY` esté configurada en `.env`
2. En n8n, verifica que la credencial de Groq esté configurada en el workflow
3. Prueba el nodo Groq individualmente desde el editor de n8n
