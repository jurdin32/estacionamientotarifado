# Integración WebSocket — Backend Django

## Resumen

La app Flutter ahora soporta **WebSocket** como canal principal de sincronización
en tiempo real, reemplazando el polling HTTP cada 4 segundos. Esto reduce
drásticamente el consumo de memoria, batería y ancho de banda.

**Arquitectura:**
- **WebSocket activo** → la app recibe push de datos en tiempo real  
- **Polling HTTP (fallback)** → cada 15s, solo si el WebSocket está caído

---

## URL del WebSocket

```
wss://simert.transitoelguabo.gob.ec/ws/sync/?token=<TOKEN_DRF>
```

---

## Protocolo de Mensajes (JSON)

### 1. Autenticación
El token DRF se envía como query parameter `?token=...`.
El backend debe validar el token al aceptar la conexión.

### 2. Suscripción a canales

**Cliente → Servidor:**
```json
{"tipo": "suscribir", "canal": "estaciones"}
{"tipo": "suscribir", "canal": "tarjetas"}
{"tipo": "suscribir", "canal": "multas"}
{"tipo": "suscribir", "canal": "notificaciones"}
{"tipo": "desuscribir", "canal": "estaciones"}
```

### 3. Heartbeat (mantener conexión)

**Cliente → Servidor:**
```json
{"tipo": "ping"}
```

**Servidor → Cliente:**
```json
{"tipo": "pong"}
```

### 4. Eventos del servidor → cliente

Todos los mensajes siguen esta estructura:

```json
{
  "canal": "estaciones",
  "accion": "snapshot|update|delete",
  "datos": { ... }
}
```

#### Canal: `estaciones`

**Snapshot completo** (al suscribirse o periódicamente):
```json
{
  "canal": "estaciones",
  "accion": "snapshot",
  "datos": [
    {"id": 1, "numero": 1, "direccion": "Calle X", "placa": "ABC1234", "estado": true},
    {"id": 2, "numero": 2, "direccion": "Calle Y", "placa": "", "estado": false}
  ]
}
```

**Actualización individual** (cuando una estación cambia):
```json
{
  "canal": "estaciones",
  "accion": "update",
  "datos": {"id": 1, "numero": 1, "direccion": "Calle X", "placa": "XYZ9876", "estado": true}
}
```

#### Canal: `tarjetas`

**Snapshot completo** (registros de estacionamiento-tarjeta activos):
```json
{
  "canal": "tarjetas",
  "accion": "snapshot",
  "datos": [
    {
      "fecha": "2026-03-20",
      "hora_entrada": "08:30:00",
      "hora_salida": "09:00:00",
      "tiempo": 30,
      "estacion": 1,
      "t": 5,
      "placa": "ABC1234",
      "usuario": 3
    }
  ]
}
```

**Actualización individual:**
```json
{
  "canal": "tarjetas",
  "accion": "update",
  "datos": {
    "fecha": "2026-03-20",
    "hora_entrada": "08:30:00",
    "hora_salida": "09:00:00",
    "tiempo": 30,
    "estacion": 1,
    "t": 5,
    "placa": "ABC1234",
    "usuario": 3
  }
}
```

**Eliminación (liberación de espacio):**
```json
{
  "canal": "tarjetas",
  "accion": "delete",
  "datos": {"estacion": 1}
}
```

**Actualización de tiempo consumido en tarjeta:**
```json
{
  "canal": "tarjetas",
  "accion": "tiempo",
  "datos": {"numero": 5, "tiempo": 45}
}
```

#### Canal: `multas`

**Snapshot completo** (al suscribirse — multas/infracciones del mes):
```json
{
  "canal": "multas",
  "accion": "snapshot",
  "datos": [
    {
      "id": 10,
      "fechaEmision": "2026-06-15T10:30:00",
      "placa": "ABC1234",
      "tipoMulta": "Parqueo indebido",
      "valor": 25.00,
      "usuario": 3
    }
  ]
}
```

**Creación de nueva multa:**
```json
{
  "canal": "multas",
  "accion": "create",
  "datos": {
    "id": 11,
    "fechaEmision": "2026-06-20T14:00:00",
    "placa": "XYZ9876",
    "tipoMulta": "Estacionamiento expirado",
    "valor": 15.00,
    "usuario": 3
  }
}
```

> **Uso en Flutter:** HomeScreen se suscribe a `multas` para actualizar las
> métricas de infracciones del mes en tiempo real (contadores e indicadores).

#### Canal: `notificaciones`

**Snapshot completo** (notificaciones del usuario autenticado):
```json
{
  "canal": "notificaciones",
  "accion": "snapshot",
  "datos": [
    {
      "id": 50,
      "cedula": "0701234567",
      "placa": "ABC1234",
      "fechaEmision": "2026-06-15",
      "estado": "impaga",
      "usuario": 3,
      "operador": "ADMIN"
    }
  ]
}
```

**Nueva notificación creada:**
```json
{
  "canal": "notificaciones",
  "accion": "create",
  "datos": {
    "id": 51,
    "cedula": "0707654321",
    "placa": "DEF5678",
    "fechaEmision": "2026-06-20",
    "estado": "impaga",
    "usuario": 3,
    "operador": "ADMIN"
  }
}
```

> **Uso en Flutter:** Notificacionusuario se suscribe a `notificaciones`
> para recibir multas nuevas y cambios de estado (pagadas, impugnadas) al instante.

---

## Implementación Backend (Django Channels)

### 1. Instalar dependencias

```bash
pip install channels channels-redis daphne
```

### 2. Configurar `settings.py`

```python
INSTALLED_APPS = [
    'daphne',
    'channels',
    # ... tus apps existentes
]

ASGI_APPLICATION = 'tuproyecto.asgi.application'

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': [('127.0.0.1', 6379)],
        },
    },
}
```

### 3. Crear `asgi.py`

```python
import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from .ws_auth import TokenAuthMiddleware
from . import ws_routing

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'tuproyecto.settings')

application = ProtocolTypeRouter({
    'http': get_asgi_application(),
    'websocket': AllowedHostsOriginValidator(
        TokenAuthMiddleware(
            URLRouter(ws_routing.websocket_urlpatterns)
        )
    ),
})
```

### 4. Crear middleware de autenticación `ws_auth.py`

```python
from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from rest_framework.authtoken.models import Token


class TokenAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        query_string = parse_qs(scope.get('query_string', b'').decode())
        token_key = query_string.get('token', [None])[0]
        if token_key:
            scope['user'] = await self.get_user(token_key)
        return await super().__call__(scope, receive, send)

    @database_sync_to_async
    def get_user(self, token_key):
        try:
            return Token.objects.get(key=token_key).user
        except Token.DoesNotExist:
            from django.contrib.auth.models import AnonymousUser
            return AnonymousUser()
```

### 5. Crear routing `ws_routing.py`

```python
from django.urls import re_path
from . import ws_consumers

websocket_urlpatterns = [
    re_path(r'ws/sync/$', ws_consumers.SyncConsumer.as_asgi()),
]
```

### 6. Crear consumer `ws_consumers.py`

```python
import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser


class SyncConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer para sincronización en tiempo real."""

    async def connect(self):
        user = self.scope.get('user')
        if isinstance(user, AnonymousUser) or user is None:
            await self.close()
            return

        self.canales = set()
        self.group_name = 'sync_global'
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(
                self.group_name, self.channel_name
            )

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return

        tipo = data.get('tipo', '')

        if tipo == 'ping':
            await self.send(text_data=json.dumps({'tipo': 'pong'}))
        elif tipo == 'suscribir':
            canal = data.get('canal', '')
            if canal:
                self.canales.add(canal)
                # Enviar snapshot inicial al suscribirse
                await self.enviar_snapshot(canal)
        elif tipo == 'desuscribir':
            canal = data.get('canal', '')
            self.canales.discard(canal)

    async def enviar_snapshot(self, canal):
        if canal == 'estaciones':
            datos = await self.get_estaciones()
            await self.send(text_data=json.dumps({
                'canal': 'estaciones',
                'accion': 'snapshot',
                'datos': datos,
            }))
        elif canal == 'tarjetas':
            datos = await self.get_tarjetas()
            await self.send(text_data=json.dumps({
                'canal': 'tarjetas',
                'accion': 'snapshot',
                'datos': datos,
            }))
        elif canal == 'multas':
            datos = await self.get_multas()
            await self.send(text_data=json.dumps({
                'canal': 'multas',
                'accion': 'snapshot',
                'datos': datos,
            }))
        elif canal == 'notificaciones':
            user = self.scope.get('user')
            datos = await self.get_notificaciones(user)
            await self.send(text_data=json.dumps({
                'canal': 'notificaciones',
                'accion': 'snapshot',
                'datos': datos,
            }))

    async def sync_broadcast(self, event):
        """Recibe broadcasts del channel layer y los reenvía al cliente
        solo si está suscrito al canal correspondiente."""
        canal = event.get('canal', '')
        if canal in self.canales:
            await self.send(text_data=json.dumps({
                'canal': canal,
                'accion': event.get('accion', 'update'),
                'datos': event.get('datos'),
            }))

    @database_sync_to_async
    def get_estaciones(self):
        from tuapp.models import Estacion  # Ajustar import
        return list(
            Estacion.objects.values('id', 'numero', 'direccion', 'placa', 'estado')
        )

    @database_sync_to_async
    def get_tarjetas(self):
        from tuapp.models import EstacionTarjeta  # Ajustar import
        return list(
            EstacionTarjeta.objects.filter(estacion__gt=0).values(
                'fecha', 'hora_entrada', 'hora_salida', 'tiempo',
                'estacion', 't', 'placa', 'usuario',
            )
        )

    @database_sync_to_async
    def get_multas(self):
        from tuapp.models import DetalleMulta  # Ajustar import y modelo
        from django.utils import timezone
        now = timezone.now()
        return list(
            DetalleMulta.objects.filter(
                fechaEmision__year=now.year,
                fechaEmision__month=now.month,
            ).values('id', 'fechaEmision', 'placa', 'tipoMulta', 'valor', 'usuario')
        )

    @database_sync_to_async
    def get_notificaciones(self, user):
        from tuapp.models import Notificacion  # Ajustar import y modelo
        qs = Notificacion.objects.all()
        if user and user.is_authenticated and not user.is_superuser:
            qs = qs.filter(usuario=user)
        return list(qs.values(
            'id', 'cedula', 'placa', 'fechaEmision', 'estado', 'usuario', 'operador',
        ))
```

### 7. Emitir eventos desde las vistas REST

Cuando la API REST modifica una estación o tarjeta, debe notificar
al canal WebSocket para que todos los clientes conectados reciban
la actualización:

```python
# utils_ws.py
from channels.layers import get_channel_layer
from asgiref.sync import async_to_sync


def broadcast_estacion_update(estacion_data):
    """Llamar después de PUT/PATCH en /api/estacion/{id}/"""
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        'sync_global',
        {
            'type': 'sync.broadcast',
            'canal': 'estaciones',
            'accion': 'update',
            'datos': estacion_data,
        }
    )


def broadcast_tarjeta_update(tarjeta_data):
    """Llamar después de POST en /api/est_tarjeta/"""
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        'sync_global',
        {
            'type': 'sync.broadcast',
            'canal': 'tarjetas',
            'accion': 'update',
            'datos': tarjeta_data,
        }
    )


def broadcast_tarjeta_delete(estacion_id):
    """Llamar cuando se libera un estacionamiento."""
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        'sync_global',
        {
            'type': 'sync.broadcast',
            'canal': 'tarjetas',
            'accion': 'delete',
            'datos': {'estacion': estacion_id},
        }
    )


def broadcast_multa_create(multa_data):
    """Llamar después de crear una nueva multa/infracción."""
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        'sync_global',
        {
            'type': 'sync.broadcast',
            'canal': 'multas',
            'accion': 'create',
            'datos': multa_data,
        }
    )


def broadcast_notificacion_create(notificacion_data):
    """Llamar después de crear una nueva notificación."""
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(
        'sync_global',
        {
            'type': 'sync.broadcast',
            'canal': 'notificaciones',
            'accion': 'create',
            'datos': notificacion_data,
        }
    )
```

**En tus ViewSets/Views existentes:**
```python
# views.py (ejemplo para Estacion)
from .utils_ws import broadcast_estacion_update

class EstacionViewSet(viewsets.ModelViewSet):
    # ...
    def update(self, request, *args, **kwargs):
        response = super().update(request, *args, **kwargs)
        if response.status_code == 200:
            broadcast_estacion_update(response.data)
        return response
```

---

## Despliegue en Ubuntu con Apache2 + Celery

> Tu configuración actual: Apache2 (mod_wsgi) para HTTP + Celery para tareas en
> segundo plano. Apache2 **no soporta WebSocket**, así que necesitas Daphne como
> servidor ASGI paralelo y Apache2 como proxy inverso para las rutas `/ws/`.

### Paso 1: Instalar dependencias

```bash
pip install channels channels-redis daphne
sudo apt install redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server
```

### Paso 2: Habilitar módulos de Apache para proxy WebSocket

```bash
sudo a2enmod proxy proxy_http proxy_wstunnel
sudo systemctl restart apache2
```

### Paso 3: Configurar Apache2 como proxy WebSocket

Edita tu VirtualHost (ej: `/etc/apache2/sites-available/simert.conf`):

```apache
<VirtualHost *:443>
    ServerName simert.transitoelguabo.gob.ec

    # ── Tu configuración SSL existente ──
    SSLEngine on
    SSLCertificateFile /ruta/a/tu/cert.pem
    SSLCertificateKeyFile /ruta/a/tu/key.pem

    # ── WebSocket: proxy a Daphne ───────────────────────────────
    # IMPORTANTE: estas reglas ANTES de las reglas WSGI
    ProxyPreserveHost On

    # Ruta /ws/ → Daphne (puerto 8001)
    ProxyPass /ws/ ws://127.0.0.1:8001/ws/
    ProxyPassReverse /ws/ ws://127.0.0.1:8001/ws/

    # ── HTTP normal: mod_wsgi (tu configuración existente) ──────
    WSGIDaemonProcess simert python-home=/ruta/a/tu/venv python-path=/ruta/a/tu/proyecto
    WSGIProcessGroup simert
    WSGIScriptAlias / /ruta/a/tu/proyecto/tuproyecto/wsgi.py

    # Archivos estáticos
    Alias /static/ /ruta/a/tu/static/
    <Directory /ruta/a/tu/static/>
        Require all granted
    </Directory>

    # ...resto de tu configuración actual
</VirtualHost>
```

### Paso 4: Crear servicio systemd para Daphne

```bash
sudo nano /etc/systemd/system/daphne-simert.service
```

```ini
[Unit]
Description=Daphne WebSocket Server para SIMERT
After=network.target redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/ruta/a/tu/proyecto
Environment="DJANGO_SETTINGS_MODULE=tuproyecto.settings"
ExecStart=/ruta/a/tu/venv/bin/daphne \
    -b 127.0.0.1 \
    -p 8001 \
    tuproyecto.asgi:application
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable daphne-simert
sudo systemctl start daphne-simert
sudo systemctl status daphne-simert
```

### Paso 5: Emitir broadcasts desde Celery tasks

Si tienes tareas Celery que modifican estaciones o tarjetas, agrega
los broadcasts al final de cada task:

```python
# tasks.py
from celery import shared_task
from .utils_ws import broadcast_estacion_update, broadcast_tarjeta_update

@shared_task
def procesar_estacion(estacion_id):
    """Ejemplo: task de Celery que modifica una estación."""
    from tuapp.models import Estacion
    estacion = Estacion.objects.get(id=estacion_id)
    # ... tu lógica existente ...
    estacion.save()

    # Notificar a todos los clientes WebSocket conectados
    broadcast_estacion_update({
        'id': estacion.id,
        'numero': estacion.numero,
        'direccion': estacion.direccion,
        'placa': estacion.placa,
        'estado': estacion.estado,
    })

@shared_task
def liberar_estacion_expirada(estacion_id):
    """Ejemplo: task que libera estaciones vencidas."""
    from tuapp.models import Estacion
    estacion = Estacion.objects.get(id=estacion_id)
    estacion.placa = ''
    estacion.estado = False
    estacion.save()

    broadcast_estacion_update({
        'id': estacion.id,
        'numero': estacion.numero,
        'direccion': estacion.direccion,
        'placa': '',
        'estado': False,
    })
```

> **Nota:** `broadcast_estacion_update()` y las funciones de `utils_ws.py`
> usan `async_to_sync(channel_layer.group_send(...))` que funciona
> correctamente tanto desde vistas Django como desde tasks de Celery,
> siempre que Redis esté corriendo y accesible.

### Paso 6: Verificar que todo funciona

```bash
# 1. Verificar Redis
redis-cli ping
# Debe responder: PONG

# 2. Verificar Daphne
sudo systemctl status daphne-simert

# 3. Probar WebSocket desde terminal
# Instalar wscat si no lo tienes:
sudo npm install -g wscat

# Conectar (reemplaza TOKEN por un token DRF válido):
wscat -c "wss://simert.transitoelguabo.gob.ec/ws/sync/?token=TU_TOKEN"
# Enviar ping:
> {"tipo": "ping"}
# Debe responder: {"tipo": "pong"}

# 4. Verificar logs
sudo journalctl -u daphne-simert -f
```

### Arquitectura final

```
                    Internet
                       │
                       ▼
              ┌────────────────┐
              │   Apache2 :443 │
              │   (SSL + Proxy)│
              └───────┬────────┘
                      │
           ┌──────────┴──────────┐
           │                     │
     /ws/* rutas          / rutas HTTP
           │                     │
           ▼                     ▼
   ┌──────────────┐    ┌──────────────┐
   │ Daphne :8001 │    │ mod_wsgi     │
   │ (ASGI/WS)    │    │ (Django HTTP) │
   └──────┬───────┘    └──────┬───────┘
          │                   │
          └─────────┬─────────┘
                    │
              ┌─────▼─────┐
              │  Redis     │
              │ :6379      │
              └─────┬──────┘
                    │
              ┌─────▼─────┐
              │  Celery    │
              │  Worker    │
              └────────────┘
```

### Opción B: Redis
Necesitas Redis corriendo para el channel layer:
```bash
sudo apt install redis-server
sudo systemctl enable redis-server
```

---

## Resumen de cambios en Flutter

| Archivo | Cambio |
|---------|--------|
| `pubspec.yaml` | Agregado `web_socket_channel: ^3.0.2` |
| `lib/servicios/servicioWebSocket.dart` | **NUEVO** — Servicio singleton WebSocket con monitoreo de datos |
| `lib/servicios/monitorDatos.dart` | **NUEVO** — Servicio singleton de monitoreo de consumo de datos |
| `lib/servicios/httpMonitorizado.dart` | **NUEVO** — Wrapper HTTP que registra consumo automáticamente |
| `lib/consultas/monitor_datos_screen.dart` | **NUEVO** — Pantalla de consumo de datos (resumen + historial) |
| `lib/tarjetas/views/EstacionamientoScreen.dart` | WS como canal principal, HTTP como fallback cada 15s |
| `lib/home_screen.dart` | Cache-first + suscripción WS a `multas` y `tarjetas` para métricas en vivo |
| `lib/tarjetas/views/Notificacionusuario.dart` | Suscripción WS a `notificaciones` para historial en tiempo real |
| `lib/admin/estaciones_screen.dart` | Suscripción WS a `estaciones` para CRUD admin en tiempo real |
| `lib/servicios/servicioTiposMultas.dart` | Migrado de `http.get` a `HttpMonitorizado.get` |
| `lib/servicios/servicioNotificaciones2.dart` | Migrado de `http.get` a `HttpMonitorizado.get` |
| Todos los servicios y pantallas HTTP | Migrados a `HttpMonitorizado` para tracking automático |

---

## Beneficios

| Antes (Polling) | Después (WebSocket) |
|------------------|---------------------|
| 3 HTTP requests cada 4s | 0 requests (push desde servidor) |
| ~45 requests/min | ~2 requests/min (heartbeat) |
| Latencia 4s para ver cambios | Latencia <100ms |
| Alto consumo de batería | Bajo consumo (conexión persistente) |
| Fallback: sin datos si falla | Fallback: polling HTTP cada 15s |
