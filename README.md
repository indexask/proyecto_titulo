# GyGTrack

Sistema Integral de Gestión Comercial y Trazabilidad Logística para **GyG Comercial**.
Proyecto de Título, Ingeniería en Informática, INACAP.

- **Administrador**: panel web/escritorio con adjudicaciones, rentabilidad, catálogo, rutas y alertas.
- **Chofer**: app móvil (Android/iOS) con despachos, cambio de estado offline-first, ruta del día y alertas push. No ve información financiera.

Stack: Flutter (Dart) · Supabase (PostgreSQL, Auth, Edge Functions, CRON) · Google Maps (Routes, Places) ·
Firebase Cloud Messaging **únicamente como canal de envío de notificaciones push**.
Decisiones, trazabilidad de requerimientos y pendientes: [docs/DECISIONES_IMPLEMENTACION.md](docs/DECISIONES_IMPLEMENTACION.md).

## Puesta en marcha

### 1. Respaldar el prototipo (obligatorio antes de migrar)

La migración `20261112000000_gygtrack_modelo.sql` **borra** las tablas del prototipo
(`profiles` pasa a ser `usuario`; se eliminan `cotizaciones`, `rutas` y `puntos_ruta`).
Primero hay que respaldarlas. No se necesita Docker:

```powershell
cd supabase/respaldo
npm install
$env:DATABASE_URL = "<Supabase → Connect → Session pooler>"
npm run respaldar        # crea respaldos/prototipo_<fecha>.json y .sql
```

Antes de seguir, revisa que el respaldo tenga las filas esperadas. La carpeta `respaldos/` no se versiona.
Si tienes Docker, también sirve `supabase db dump --data-only -f respaldo.sql`.

### 2. Supabase

```bash
supabase link --project-ref <ref-del-proyecto>
supabase db push                      # recién después del respaldo
supabase secrets set GOOGLE_MAPS_API_KEY=<clave-servidor>   # Routes API + Places API (New)
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat cuenta-servicio.json)"   # push (ver §4)
supabase functions deploy geocodificar
supabase functions deploy optimizar-ruta
supabase functions deploy importar-cotizacion
supabase functions deploy enviar-alertas   # con verificación JWT (ver paso 4 de abajo)
```

En el panel de Supabase:

1. **Authentication → Sign In / Providers**: desactivar *Allow new users to sign up*.
2. **Authentication → Users**: crear las cuentas. Nacen como Chofer. Para el Administrador:
   `update public.usuario set rol = 'administrador', nombre = 'Javier Gómez' where id = '<uuid>';`
3. **Database → Extensions**: verificar que `pg_cron` y `pg_net` estén activas (las migraciones las habilitan).
4. **SQL Editor**: guardar en Vault los datos para que el CRON dispare el envío push:
   ```sql
   select vault.create_secret('https://<ref>.supabase.co', 'gygtrack_url_proyecto');
   -- service_role en formato JWT ("eyJ..."; Settings → API Keys → Legacy API keys):
   select vault.create_secret('<service_role JWT>', 'gygtrack_service_role_key');
   ```

### 3. Claves de la app (no se versionan)

| Archivo | Plantilla | Contenido |
|---|---|---|
| `env/dev.json` | `env/dev.json.example` | `SUPABASE_URL`, `SUPABASE_ANON_KEY` y, opcionalmente, `FIREBASE_*` (push) |
| `android/secrets.properties` | `android/secrets.properties.example` | `MAPS_API_KEY` (Maps SDK for Android) |
| `ios/Flutter/Secrets.xcconfig` | `ios/Flutter/Secrets.xcconfig.example` | `MAPS_API_KEY` (Maps SDK for iOS) |
| `web/maps_config.js` | `web/maps_config.js.example` | Clave de Maps JavaScript API (restringir por referrer) |

### 4. Notificaciones push (FCM)

1. Crear un proyecto en [Firebase](https://console.firebase.google.com) y registrar la app Android
   (`com.proyectotitulo.cotizaciones_rutas`) y la iOS.
2. Copiar a `env/dev.json`: `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`,
   `FIREBASE_APP_ID_ANDROID` y `FIREBASE_APP_ID_IOS`. Si quedan vacías, la app funciona sin push.
3. *Configuración del proyecto → Cuentas de servicio → Generar nueva clave privada*: ese JSON va en el
   secreto `FIREBASE_SERVICE_ACCOUNT` (paso 2). No se versiona.
4. iOS: subir la clave APNs en *Cloud Messaging* y activar *Push Notifications* en Xcode.

### 5. Ejecutar

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=env/dev.json     # panel del Administrador
flutter run -d <android> --dart-define-from-file=env/dev.json  # app del Chofer
```

## Pruebas

```bash
flutter test                                        # dominio + lógica offline
cd supabase/pruebas && npm install && npm test      # BD (PostgreSQL real), respaldo, reglas de ruta y push
```
