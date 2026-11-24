# Manual de Despliegue Técnico — GyGTrack

Instrucciones de compilación y puesta en marcha de GyGTrack (panel web del
Administrador y aplicación móvil del Chofer). Pensado como anexo técnico del
informe. Audiencia: personal técnico que compila y despliega el sistema.

> Complementa al [README.md](../README.md) y a
> [DECISIONES_IMPLEMENTACION.md](DECISIONES_IMPLEMENTACION.md).

---

## 1. Arquitectura y stack

GyGTrack es una app **Flutter** (un solo código para web y móvil) con backend
**Supabase**.

| Capa | Tecnología |
|---|---|
| Presentación | Flutter / Dart (panel web del Administrador y app Android/iOS del Chofer) |
| Lógica / estado | Riverpod, go_router |
| Backend | Supabase: PostgreSQL + Auth + Edge Functions (Deno/TypeScript) + pg_cron + pg_net + Vault |
| Mapas y rutas | Google Maps Platform: Routes API, Places API (New), Maps JavaScript API, Maps SDK Android/iOS |
| Notificaciones push | Firebase Cloud Messaging (**solo como canal de envío**) |

---

## 2. Requisitos (herramientas en el equipo de compilación)

| Herramienta | Versión usada | Para qué |
|---|---|---|
| Flutter | 3.50.0 | Compilar web y móvil |
| Dart SDK | ≥ 3.13.1 (incluido en Flutter) | — |
| Node.js | LTS | Pruebas de BD y Edge Functions |
| Supabase CLI | reciente | Migraciones y despliegue de funciones |
| Android Studio + SDK + NDK | NDK heredado del canal de Flutter | Compilar e instalar la app Android |
| Git | — | Repositorio |

No se requiere Docker para el flujo normal (el respaldo de la base se hace con un
script propio). Xcode/macOS solo se usa en la nube (Codemagic) para iOS.

Verificación rápida:

```bash
flutter --version
flutter doctor
supabase --version
node --version
```

---

## 3. Estructura del repositorio

```
proyecto_titulo/
├── lib/                       # Código Flutter (4 módulos)
│   ├── core/                  # Supabase client, router, env, almacén local…
│   └── modulos/
│       ├── gestion_comercial/         # Órdenes, productos, rentabilidad, cotizaciones
│       ├── logistico_notificaciones/  # Despachos del Chofer, alertas, offline
│       ├── enrutamiento/              # Rutas, mapa, optimización, TAG
│       └── administracion_seguridad/  # Login, roles, panel
├── web/                       # index.html + maps_config.js (clave web)
├── android/ · ios/            # Proyectos nativos
├── test/                      # Pruebas Flutter
├── supabase/
│   ├── migrations/            # Esquema (10 migraciones)
│   ├── functions/             # Edge Functions (geocodificar, optimizar-ruta,
│   │                          #   importar-cotizacion, enviar-alertas)
│   ├── pruebas/               # Pruebas de BD (PGlite) y de funciones
│   ├── datos/tag/             # Tarifas y pórticos TAG (generador)
│   └── respaldo/              # Script de respaldo del prototipo
├── env/dev.json               # Variables de la app (NO versionado)
├── codemagic.yaml             # CI de iOS (plantilla)
└── docs/                      # Documentación
```

---

## 4. Claves y archivos de configuración (secretos)

Ninguna clave se versiona. Cada archivo tiene su plantilla `*.example`; se copia sin
el sufijo y se completan los valores.

| Archivo (no versionado) | Plantilla | Contenido |
|---|---|---|
| `env/dev.json` | `env/dev.json.example` | URL y **anon key** pública de Supabase; IDs de Firebase (para push). Se inyecta con `--dart-define-from-file`. |
| `web/maps_config.js` | `web/maps_config.js.example` | Clave de **Maps JavaScript API** (panel web). Variable `window.GYGTRACK_MAPS_KEY`. Restringir por **referrer HTTP**. |
| `android/secrets.properties` | `android/secrets.properties.example` | Clave de **Maps SDK for Android** (`MAPS_API_KEY`). La lee `android/app/build.gradle.kts` y la inyecta en el manifiesto. |
| `ios/Flutter/Secrets.xcconfig` | `ios/Flutter/Secrets.xcconfig.example` | Clave de **Maps SDK for iOS** (`MAPS_API_KEY`). La usa `Info.plist` (`GMSApiKey`). |

`env/dev.json`:

```json
{
  "SUPABASE_URL": "https://<ref>.supabase.co",
  "SUPABASE_ANON_KEY": "<anon key pública>",
  "FIREBASE_API_KEY": "",
  "FIREBASE_PROJECT_ID": "",
  "FIREBASE_MESSAGING_SENDER_ID": "",
  "FIREBASE_APP_ID_ANDROID": "",
  "FIREBASE_APP_ID_IOS": ""
}
```

Las claves `String.fromEnvironment(...)` de `lib/core/env.dart` deben coincidir con
las llaves de ese JSON.

### Secretos del lado servidor (no van en la app)

- **Supabase → Edge Functions secrets:** `GOOGLE_MAPS_API_KEY` (clave de servidor con
  Routes API + Places API New) y `FIREBASE_SERVICE_ACCOUNT` (JSON de la cuenta de
  servicio de Firebase, para el push).
- **Supabase → Vault** (para que el CRON dispare el push): `gygtrack_url_proyecto` y
  `gygtrack_service_role_key` (ver paso 6.4).

---

## 5. Google Cloud (claves de Maps/Routes)

Se usan **cuatro** claves en el mismo proyecto de Google Cloud, cada una restringida:

| Clave | API habilitada | Restricción de aplicación |
|---|---|---|
| Servidor | Routes API + Places API (New) | Ninguna / por IP (vive solo en Supabase) |
| Web | Maps JavaScript API | Referrer HTTP (dominio del panel) |
| Android | Maps SDK for Android | App Android: paquete `com.proyectotitulo.cotizaciones_rutas` + huella **SHA-1** del certificado de firma |
| iOS | Maps SDK for iOS | App iOS: bundle `com.proyectotitulo.cotizacionesRutas` |

Para obtener la **SHA-1** del certificado de depuración (instalación directa):

```bash
keytool -J-Duser.language=en -list -v \
  -keystore "$HOME/.android/debug.keystore" \
  -alias androiddebugkey -storepass android -keypass android
```

> Para una app firmada con clave de **release** o publicada en Play Store, hay que
> agregar también la SHA-1 de esa clave a la restricción de la clave de Android.

---

## 6. Backend (Supabase)

### 6.1 Enlazar el proyecto

```bash
supabase link --project-ref <ref-del-proyecto>
```

### 6.2 Respaldo (obligatorio antes de migrar)

La primera migración de modelo **borra** las tablas del prototipo. Respaldar antes:

```bash
cd supabase/respaldo
npm install
export DATABASE_URL="<Supabase → Connect → Session pooler>"   # (PowerShell: $env:DATABASE_URL=...)
npm run respaldar            # genera respaldos/prototipo_<fecha>.json y .sql
```

Revisar que el respaldo tenga las filas esperadas. `respaldos/` no se versiona.
(Si hay Docker, también sirve `supabase db dump --data-only -f respaldo.sql`.)

### 6.3 Aplicar las migraciones

```bash
supabase db push            # aplica las 10 migraciones en orden
```

Migraciones (orden cronológico):

1. `20260825000000_init.sql` — base del prototipo (auth, profiles).
2. `20260826000000_cotizaciones_rutas_v2.sql`
3. `20261112000000_gygtrack_modelo.sql` — modelo GyGTrack (usuario, producto,
   orden_compra, detalle_orden, despacho, alerta, ruta, ruta_parada), RLS, vistas del
   Chofer, KPIs, alertas (pg_cron).
4. `20261112000100_push_fcm.sql` — tabla de dispositivos y disparo del push (pg_net/Vault).
5. `20261112000200_importar_cotizacion.sql`
6. `20261112000300_ruta_detalle_optimizacion.sql`
7. `20261113000000_porticos_tag.sql` — 114 pórticos TAG urbanos.
8. `20261114000000_peajes_interurbanos.sql` — 47 peajes de accesos a Santiago.
9. `20261114000100_elegir_alternativa_ruta.sql` — cambiar la alternativa de ruta.
10. `20261117000000_despacho_no_entregado.sql` — estado "No entregado" + justificación.

### 6.4 Secretos, Vault y extensiones

```bash
# Clave de servidor de Google (Routes + Places) para geocodificar y optimizar-ruta
supabase secrets set GOOGLE_MAPS_API_KEY=<clave-servidor>

# Cuenta de servicio de Firebase (push)
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat cuenta-servicio.json)"
```

En el **SQL Editor** de Supabase (para que el CRON dispare el push):

```sql
select vault.create_secret('https://<ref>.supabase.co', 'gygtrack_url_proyecto');
select vault.create_secret('<service_role JWT (eyJ...)>', 'gygtrack_service_role_key');
```

Verificar en **Database → Extensions** que `pg_cron` y `pg_net` estén activas (las
migraciones las habilitan).

### 6.5 Desplegar las Edge Functions

```bash
supabase functions deploy geocodificar
supabase functions deploy optimizar-ruta
supabase functions deploy importar-cotizacion
supabase functions deploy enviar-alertas
```

### 6.6 Cuentas y roles (Authentication)

1. **Authentication → Providers:** desactivar *Allow new users to sign up*.
2. **Authentication → Users:** crear las cuentas. Nacen como **Chofer**.
3. Para el **Administrador**:

```sql
update public.usuario
   set rol = 'administrador', nombre = 'Javier Gómez'
 where id = '<uuid del usuario>';
```

---

## 7. Compilar y ejecutar la app

Todos los comandos se corren en la raíz del proyecto Flutter e inyectan las variables
con `--dart-define-from-file=env/dev.json`.

### 7.1 Panel web (Administrador)

Desarrollo (perfil de Chrome persistente para no perder la sesión):

```bash
flutter run -d chrome --web-port 8080 \
  --dart-define-from-file=env/dev.json \
  --web-browser-flag="--user-data-dir=%LOCALAPPDATA%\gygtrack-chrome-dev"
```

Compilación para producción (requiere `web/maps_config.js` con la clave web):

```bash
flutter build web --dart-define-from-file=env/dev.json
# Publica el contenido de build/web/ en el hosting elegido.
```

### 7.2 App Android (Chofer)

Requiere `android/secrets.properties` con la clave de Maps para Android.

Instalar en un teléfono conectado por USB (con depuración USB activada):

```bash
flutter devices                              # confirmar que aparece el teléfono
flutter run -d <id-del-dispositivo> --dart-define-from-file=env/dev.json
```

Generar e instalar el **APK de release** (queda instalado de forma permanente):

```bash
flutter build apk --release --dart-define-from-file=env/dev.json
# APK en: build/app/outputs/flutter-apk/app-release.apk  (~58 MB)
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Para instalar en otro teléfono sin cable: compartir ese `.apk`, abrirlo y permitir
"instalar de esta fuente".

> El APK de release se firma con el certificado de depuración (apto para pruebas /
> defensa). Para Play Store se debe configurar una **firma de release propia** y
> agregar su SHA-1 a la clave de Android en Google Cloud.

### 7.3 App iOS (Chofer) — sin Mac

Se compila en la nube con **Codemagic** (`codemagic.yaml`) y se distribuye por
**TestFlight**. Requisitos:

1. Cuenta **Apple Developer Program** (US$99/año).
2. Cuenta en codemagic.io enlazada al repositorio.
3. En Codemagic: grupo de variables `app_secrets` (`SUPABASE_URL`,
   `SUPABASE_ANON_KEY`, `MAPS_API_KEY`, y los `FIREBASE_*` para push) y la firma iOS
   (**App settings → iOS code signing**).

El workflow genera `env/dev.json` y `ios/Flutter/Secrets.xcconfig`, corre
`flutter build ipa` y (configurado el *publishing*) sube a TestFlight.

---

## 8. Notificaciones push (Firebase Cloud Messaging)

FCM se usa **solo como canal de envío**. Pasos:

1. Crear el proyecto en Firebase con los apps Android/iOS (mismos identificadores).
2. Completar los `FIREBASE_*` en `env/dev.json`.
3. Cargar la **cuenta de servicio** en Supabase (`FIREBASE_SERVICE_ACCOUNT`, paso 6.4).
4. Para iOS, además, subir la **clave APNs** a Firebase.

El envío lo hace la Edge Function `enviar-alertas` (HTTP v1 de FCM), disparada por el
CRON `generar_alertas` (cada hora) vía pg_net/Vault.

---

## 9. Pruebas

**Base de datos y Edge Functions** (PostgreSQL real con PGlite + `node --test`):

```bash
cd supabase/pruebas
npm install
npm test        # migraciones, RLS, vistas, triggers, RPC, alertas, KPI, rutas, TAG
```

**Flutter** (unitarias y de widget):

```bash
flutter test
```

---

## 10. Solución de problemas

- **`db push` pide confirmación / borra tablas:** la primera migración es
  destructiva; respaldar antes (paso 6.2). En producción, los cambios se aplican con
  consentimiento explícito.
- **`uuid_generate_v4` no existe:** el esquema usa `gen_random_uuid()` (nativo); no se
  requiere la extensión `uuid-ossp`.
- **Mapa en blanco en la app Android:** falta `android/secrets.properties` con la
  clave, o la clave de Maps SDK Android aún no está activa (tarda ~5 min). Revisar en
  el log `Authorization failure` del Maps SDK.
- **Mapa en blanco en el panel web:** falta `web/maps_config.js`, o el dominio no está
  en la restricción por referrer de la clave web.
- **`dart.exe` bloqueado por Device Guard:** si una directiva de seguridad del equipo
  bloquea el ejecutable de Dart, no se puede correr `flutter run/test/build`; hay que
  desbloquearlo en la directiva o mover Flutter a una ruta permitida. (No afecta las
  pruebas de BD/funciones, que usan Node.)
- **Despliegue de funciones requiere consentimiento:** el CLI pide `--yes` para
  cambios en producción; usarlo solo con autorización.

---

## 11. Checklist de despliegue

- [ ] Claves creadas en Google Cloud (servidor, web, Android, iOS) y restringidas.
- [ ] `env/dev.json`, `web/maps_config.js`, `android/secrets.properties`,
      `ios/Flutter/Secrets.xcconfig` completados desde sus plantillas.
- [ ] Respaldo de la base realizado y verificado.
- [ ] `supabase db push` aplicado (10 migraciones).
- [ ] Secretos de Supabase y Vault cargados; `pg_cron`/`pg_net` activas.
- [ ] Edge Functions desplegadas (4).
- [ ] Cuentas creadas; Administrador con rol asignado; registro público desactivado.
- [ ] Panel web publicado / probado.
- [ ] APK de release generado e instalado (o iOS en TestFlight).
- [ ] (Opcional) Firebase + APNs para push.
- [ ] Pruebas verdes: `cd supabase/pruebas && npm test` y `flutter test`.

---

*GyGTrack — Proyecto de Título, Ingeniería en Informática, INACAP.*
