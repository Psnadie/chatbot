# WhatsApp Bot — OpenWA + n8n + Groq

Infraestructura Docker local que integra OpenWA (gateway WhatsApp HTTP API) con n8n (automatización de workflows) y Groq (LLM). Todo corre en una red Docker interna sin dependencias externas ni túneles.

## Arquitectura

```
                  ┌─────────────────────────────────────┐
                  │          Red: bot-network           │
                  │                                     │
                  │  ┌──────────┐     ┌──────────────┐  │
                  │  │  openwa  │     │     n8n      │  │
                  │  │ :2785    │────►│ :5678        │  │
                  │  │ :2886    │     │ /webhook/    │  │
                  │  │ (nginx)  │     │   payload    │  │
                  │  └────┬─────┘     └──────┬───────┘  │
                  │       │                  │          │
                  │  POST /api/sessions/     │          │
                  │   :sessionId/messages/   │          │
                  │   send-text              │          │
                  └─────────────────────────────────────┘
                           │                         │
                    WhatsApp API              HTTP POST
                  (webhooks mensajes         (mensajes
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
├── .env                        # Variables de entorno (no subir a git)
├── .env.example                # Plantilla de variables de entorno
├── .gitignore                  # Excluye data/ y .env del repositorio
├── docker-compose.yml          # Orquestación de servicios
├── Dockerfile.openwa           # Imagen de OpenWA + nginx + Chromium
├── dashboard-nginx.conf        # Proxy inverso para dashboard
├── start-openwa.sh             # Script de arranque del contenedor
├── setup.sh                    # Script de inicialización post-arranque
├── register-webhook.sh         # Registro del webhook en OpenWA
├── n8n/
│   └── workflows/
│       └── ChatWhatsapp.json   # Workflow de n8n importable
└── data/                       # Generado automáticamente, no subir a git
    ├── openwa/                 # Persistencia de sesiones WhatsApp
    └── n8n/                    # Persistencia de n8n
```

## Configuración del archivo .env

Copia `.env.example` a `.env` y rellena los valores:

```env
OPENWA_SESSION_ID=              # Se rellena tras crear la sesión (paso 4)
OPENWA_API_KEY=                 # Se obtiene de data/openwa/.api-key (paso 3)
GROQ_API_KEY=gsk_tu_api_key     # Consola de Groq: https://console.groq.com
N8N_ENCRYPTION_KEY=             # Ver instrucciones abajo
```

### Cómo obtener N8N_ENCRYPTION_KEY

Hay dos situaciones posibles:

**Instalación desde cero** (la carpeta `data/n8n/` no existe todavía): genera una clave aleatoria antes de levantar los contenedores:

```bash
openssl rand -hex 32
```

Pega el resultado en `N8N_ENCRYPTION_KEY` del `.env` antes de hacer `docker compose up`.

**n8n ya arrancó antes** sin `N8N_ENCRYPTION_KEY` configurada: n8n generó su propia clave y la guardó en `data/n8n/config`. Léela desde ahí y úsala en el `.env`:

```bash
cat ./data/n8n/config
# Busca el campo "encryptionKey" y copia su valor
```

Si pones una clave diferente a la que ya está en `data/n8n/config`, n8n arrancará con el error `Mismatching encryption keys` y no iniciará.

## Despliegue: primer arranque

### 1. Preparar variables de entorno

```bash
cp .env.example .env
# Rellena GROQ_API_KEY y N8N_ENCRYPTION_KEY antes de continuar
```

### 2. Levantar los contenedores

```bash
docker compose up -d
```

El primer build tarda varios minutos porque clona el repositorio de OpenWA, instala dependencias, compila TypeScript, construye el dashboard React e instala Chromium.

### 3. Obtener la API key de OpenWA

```bash
bash setup.sh
```

El script espera a que OpenWA esté listo y muestra la API key generada automáticamente. También puedes leerla directamente:

```bash
cat ./data/openwa/.api-key
```

Copia el valor y ponlo en `OPENWA_API_KEY` de tu `.env`.

### 4. Crear sesión de WhatsApp

1. Abre `http://localhost:2886` en el navegador
2. Crea una sesión nueva (ej: `mi-bot`)
3. Inicia la sesión y escanea el código QR con WhatsApp desde Dispositivos vinculados
4. Espera a que la sesión aparezca como `CONNECTED`

Anota el Session ID que aparece en el dashboard y ponlo en `OPENWA_SESSION_ID` de tu `.env`.

### 5. Registrar el webhook

```bash
bash register-webhook.sh TU_SESSION_ID
```

Esto registra en OpenWA un webhook que envía los mensajes entrantes a `http://n8n:5678/webhook/payload` por la red interna Docker.

### 6. Reiniciar n8n con las variables actualizadas

Después de rellenar `OPENWA_SESSION_ID` y `OPENWA_API_KEY` en el `.env`:

```bash
docker compose down
docker compose up -d
```

Usa `down` + `up` en lugar de `restart` para que los contenedores se recreen con la nueva configuración del `.env`.

### 7. Importar el workflow en n8n

```bash
docker exec n8n n8n import:workflow --input=/workflows/ChatWhatsapp.json
```

Este paso solo es necesario la primera vez. El workflow queda guardado en `data/n8n/` y persiste en reinicios posteriores.

### 8. Activar el workflow y configurar Groq

1. Abre `http://localhost:5678`
2. Ve a **Workflows** y abre **ChatWhatsapp**
3. Abre el nodo **Groq Chat Model**, haz clic en el campo Credential y selecciona o crea la credencial de Groq con tu `GROQ_API_KEY`
4. Activa el workflow con el toggle superior derecho

### 9. Probar

Envía un mensaje de WhatsApp al número conectado. El flujo completo es:

```
WhatsApp → OpenWA (detecta mensaje entrante)
  → POST http://n8n:5678/webhook/payload
  → nodo IF filtra fromMe === false
  → AI Agent procesa con Groq Llama 3.1 8B
  → HTTP Request POST /api/sessions/:id/messages/send-text
  → respuesta enviada de vuelta a WhatsApp
```

Para monitorear en tiempo real, ve a **Executions** en n8n o revisa los logs:

```bash
docker compose logs n8n --tail=20
docker compose logs openwa --tail=20
```

## Reinicios posteriores

Una vez que el sistema estuvo funcionando, los reinicios son más simples. Los datos de sesión de WhatsApp y los workflows de n8n persisten en `data/`.

```bash
docker compose down
docker compose up -d
```

Si la sesión de OpenWA aparece como `FAILED` tras el reinicio, es porque Chromium no se cerró limpiamente. Haz clic en **Reconnect** desde el dashboard en `http://localhost:2886`. No es necesario volver a escanear el QR mientras `data/openwa/` no se haya borrado.

Si Reconnect no funciona, reinicia el contenedor de OpenWA directamente para limpiar todo el caché de Chromium:

```bash
docker compose restart openwa
```

Luego vuelve a intentar Reconnect desde el dashboard.

## Puertos expuestos

| Puerto | Servicio | Uso |
|---|---|---|
| `2785` | OpenWA API | API REST. Swagger docs en `/api/docs` |
| `2886` | OpenWA Dashboard | Panel web para gestionar sesiones |
| `5678` | n8n | Editor de workflows y webhook receptor |

## Rutas de API relevantes

### OpenWA (`localhost:2785`)

| Método | Ruta | Descripción |
|---|---|---|
| `GET` | `/api/health` | Health check |
| `GET` | `/api/docs` | Documentación Swagger |
| `GET` | `/api/sessions` | Listar sesiones |
| `POST` | `/api/sessions` | Crear sesión |
| `POST` | `/api/sessions/:id/start` | Iniciar sesión |
| `POST` | `/api/sessions/:id/webhooks` | Registrar webhook |
| `GET` | `/api/sessions/:id/webhooks` | Listar webhooks |
| `POST` | `/api/sessions/:id/messages/send-text` | Enviar mensaje de texto |

### n8n (`localhost:5678`)

| Método | Ruta | Descripción |
|---|---|---|
| `POST` | `/webhook/payload` | Webhook que recibe mensajes de OpenWA |

## Variables de entorno en n8n

El workflow usa variables de entorno del contenedor para no hardcodear credenciales. Están configuradas en `docker-compose.yml` y leídas en los nodos con `$env.NOMBRE`:

- `$env.OPENWA_SESSION_ID` — ID de sesión para construir la URL de envío
- `$env.OPENWA_API_KEY` — API key para autenticar contra OpenWA

Si n8n bloquea el acceso a `$env` con el error `access to env vars denied`, la alternativa es usar n8n Variables nativas. Ve a **Settings > Variables** en n8n y crea:

```
OPENWA_SESSION_ID = tu_session_id
OPENWA_API_KEY    = tu_api_key
```

Luego en los nodos usa `$vars.OPENWA_SESSION_ID` y `$vars.OPENWA_API_KEY` en lugar de `$env`.

## Comunicación entre contenedores

Ambos servicios están en la red bridge `bot-network`. Se comunican por nombre de contenedor:

- **OpenWA → n8n**: `http://n8n:5678/webhook/payload`
- **n8n → OpenWA**: `http://openwa:2785/api/sessions/...`

No uses `localhost` ni `host.docker.internal` para comunicación entre contenedores del mismo `docker-compose.yml`.

## Detalles técnicos

### Dockerfile.openwa

- Basado en `node:20-alpine`
- Incluye Chromium y sus dependencias (`nss`, `freetype`, `harfbuzz`, `ca-certificates`, `ttf-freefont`) para Puppeteer
- `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true` evita que Puppeteer descargue su propio Chrome
- `PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser` apunta al Chromium del sistema
- Compila el proyecto TypeScript con `npm run build`
- Construye el dashboard React si existe `dashboard/package.json`
- Parchea `@IsUrl({ require_tld: false })` en el DTO compilado para aceptar nombres de contenedor Docker como URLs de webhook
- Incluye nginx como proxy inverso para el dashboard en el puerto 2886

### dashboard-nginx.conf

Nginx escucha en el puerto 2886 y:
- Sirve los archivos estáticos del dashboard desde `/app/dashboard/dist`
- Proxy inverso `/api/*` → `localhost:2785`
- Proxy inverso `/socket.io/*` → `localhost:2785`

### start-openwa.sh

Arranca nginx en background y la API de NestJS en foreground para mantener el contenedor vivo.

### Workflow ChatWhatsapp.json

1. **Webhook** — Recibe POST en `/webhook/payload`
2. **IF** — Filtra `fromMe === false` para ignorar mensajes enviados por el propio bot
3. **AI Agent** — Agente conversacional con Groq (Llama 3.1 8B instant)
4. **HTTP Request** — Envía la respuesta a OpenWA via `POST /messages/send-text`
5. **Respond to Webhook** — Responde `{ status: "ok" }` a OpenWA

## Seguridad y git

El `.gitignore` excluye `data/` y `.env` del repositorio porque contienen:
- Sesión autenticada de WhatsApp (`data/openwa/sessions/`)
- Base de datos y credenciales cifradas de n8n (`data/n8n/`)
- API keys en texto plano (`.env`)

Usa `.env.example` como plantilla para documentar las variables necesarias sin exponer valores reales. Si accidentalmente haces commit del `.env`, limpia el historial antes de hacer push:

```bash
git rm --cached .env
git commit --amend --no-edit
git push origin main --force
```

Y rota inmediatamente cualquier API key que haya quedado expuesta.

## Troubleshooting

### "url must be a URL address" al registrar webhook

El decorador `@IsUrl()` de `class-validator` exige un TLD (`.com`) por defecto y rechaza `http://n8n:5678/...`. El Dockerfile parchea automáticamente esta validación con `require_tld: false`. Si el contenedor ya está corriendo sin el parche, aplícalo manualmente:

```bash
docker exec openwa sed -i 's/(0, class_validator_1.IsUrl)()/(0, class_validator_1.IsUrl)({ require_tld: false })/g' /app/dist/modules/webhook/dto/webhook.dto.js
docker compose restart openwa
```

### La sesión aparece como FAILED tras reiniciar

Chromium deja archivos de caché y procesos colgados cuando el contenedor se detiene bruscamente. La solución más efectiva es reiniciar el contenedor de OpenWA para limpiar todo el caché:

```bash
docker compose restart openwa
```

Luego desde el dashboard en `http://localhost:2886` haz clic en **Reconnect** sobre la sesión. No hace falta volver a escanear el QR si `data/openwa/` sigue intacto.

### Error "Mismatching encryption keys" en n8n

n8n ya tenía una clave guardada en `data/n8n/config` que no coincide con `N8N_ENCRYPTION_KEY` del `.env`. Lee la clave existente y úsala:

```bash
cat ./data/n8n/config
# Copia el valor de encryptionKey y ponlo en N8N_ENCRYPTION_KEY del .env
docker compose down && docker compose up -d
```

### El agente IA no responde

1. Verifica que `GROQ_API_KEY` esté configurada en `.env`
2. En n8n, abre el nodo **Groq Chat Model** y reasigna la credencial de Groq manualmente (el workflow importado puede tener un ID de credencial de otra instancia)
3. Prueba la conexión desde **Settings > Credentials**

### n8n no recibe mensajes de OpenWA

1. Verifica que el workflow esté activo (toggle verde)
2. Verifica que el webhook esté registrado en OpenWA:
   ```bash
   curl http://localhost:2785/api/sessions/TU_SESSION_ID/webhooks \
     -H "X-API-Key: TU_API_KEY"
   ```
3. Verifica que la sesión de WhatsApp esté en estado `CONNECTED` en el dashboard

### Cambios en docker-compose.yml no se aplican con restart

`docker compose restart` solo reinicia el proceso dentro del contenedor existente sin aplicar cambios del compose ni del `.env`. Para aplicar cambios siempre usa:

```bash
docker compose down
docker compose up -d
```