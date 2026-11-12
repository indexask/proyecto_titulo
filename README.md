# GyGTrack

Sistema Integral de Gestión Comercial y Trazabilidad Logística para **GyG Comercial**.
Proyecto de Título, Ingeniería en Informática, INACAP.

- **Administrador**: panel web/escritorio con adjudicaciones, rentabilidad, catálogo, rutas y alertas.
- **Chofer**: app móvil (Android/iOS) con despachos, cambio de estado offline-first y ruta del día. No ve información financiera.

Stack: Flutter (Dart) · Supabase (PostgreSQL, Auth, Edge Functions, CRON) · Google Maps (Routes, Places).
Decisiones, trazabilidad de requerimientos y pendientes: [docs/DECISIONES_IMPLEMENTACION.md](docs/DECISIONES_IMPLEMENTACION.md).

## Puesta en marcha

### 1. Supabase

```bash
supabase link --project-ref <ref-del-proyecto>
supabase db push                       # aplica supabase/migrations (¡borra las tablas del prototipo!)
supabase secrets set GOOGLE_MAPS_API_KEY=<clave-servidor>   # habilitar Routes API y Places API (New)
supabase functions deploy geocodificar
supabase functions deploy optimizar-ruta
```

En el panel de Supabase:

1. **Authentication → Sign In / Providers**: desactivar *Allow new users to sign up*.
2. **Authentication → Users**: crear las cuentas. Nacen como Chofer. Para el Administrador:
   `update public.usuario set rol = 'administrador', nombre = 'Javier Gómez' where id = '<uuid>';`
3. **Database → Extensions**: verificar que `pg_cron` esté activo (la migración lo habilita).

### 2. Claves de la app (no se versionan)

| Archivo | Plantilla | Contenido |
|---|---|---|
| `env/dev.json` | `env/dev.json.example` | `SUPABASE_URL`, `SUPABASE_ANON_KEY` |
| `android/secrets.properties` | `android/secrets.properties.example` | `MAPS_API_KEY` (Maps SDK for Android) |
| `ios/Flutter/Secrets.xcconfig` | `ios/Flutter/Secrets.xcconfig.example` | `MAPS_API_KEY` (Maps SDK for iOS) |
| `web/maps_config.js` | `web/maps_config.js.example` | Clave de Maps JavaScript API (restringir por referrer) |

### 3. Ejecutar

```bash
flutter pub get
flutter run -d chrome --dart-define-from-file=env/dev.json     # panel del Administrador
flutter run -d <android> --dart-define-from-file=env/dev.json  # app del Chofer
```

## Pruebas

```bash
flutter test                                        # dominio + lógica offline
cd supabase/pruebas && npm install && npm test      # base de datos (PostgreSQL real) + reglas de ruta
```
