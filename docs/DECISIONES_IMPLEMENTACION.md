# GyGTrack — Decisiones de implementación y trazabilidad

Documento de apoyo a la **Regla de Espejo** (informe ↔ aplicación). Registra qué
se conservó del prototipo, qué se cambió y por qué, cada decisión tomada donde
la especificación no decía nada, y lo que queda pendiente. Todo lo marcado como
**[VALIDAR]** debe contrastarse con el ER de la Parte 2 o confirmarse con el equipo
antes de reflejarlo en el informe.

---

## 0. Cambio en el stack documentado (actualizar el informe)

**Decisión del equipo (2026-11-12):** se agrega **Firebase Cloud Messaging (FCM) únicamente
como canal de envío de notificaciones push** (RF-19).

- FCM **no** es base de datos ni backend. Supabase sigue siendo el BaaS: PostgreSQL, Auth, Edge Functions y CRON.
- La lógica de **cuándo** alertar (3 días antes y Día Cero) sigue en Supabase (`generar_alertas` + pg_cron). FCM solo transporta el mensaje al teléfono.
- Motivo: en Android, FCM es prácticamente el único canal de push. No tiene costo.

**Texto sugerido para la tabla de stack del informe** (fila "Notificaciones"):
> Push notifications mediante **Firebase Cloud Messaging (FCM), utilizado únicamente como canal de
> envío**. La generación de alertas reside en Supabase (CRON + Edge Functions).

---

## 0.1 Importación automática de cotizaciones (solicitud del equipo, 2026-11-12)

El Administrador presiona **"Subir cotización"** en Órdenes, elige el PDF y el formulario de la orden queda completado:

| Campo de la cotización | Dónde queda |
|---|---|
| Fecha (ej. 12-08-2026) | `orden_compra.fecha_cotizacion` |
| Solicitado por | `orden_compra.cliente` |
| Dirección (del cliente, no la de GyG) | `orden_compra.direccion_entrega`; se valida sola con Places |
| Cotización (ej. 5609-132-COT26) | `orden_compra.numero_cotizacion` (única: no se puede importar dos veces) |
| Descripción, Unidades, Precio unidad, Total | Una línea de `detalle_orden` por producto. Si el producto existe en el catálogo se reutiliza; si no, se crea al guardar |
| Foto del producto | `producto.foto_path` (bucket privado `productos` de Supabase Storage) |

- **Sin IA y sin tecnologías nuevas.** La Edge Function `importar-cotizacion` lee la **plantilla propia de GyG** (etiquetas y columnas del PDF) con librerías de lectura de PDF, y extrae la foto embebida (JPEG). El PDF no sale de Supabase. Por eso no se reintroduce Gemini, que usaba el prototipo y está fuera del stack.
- **Lo que no viene en la cotización:** el **costo de compra** (necesario para el margen, RF-07) se completa solo si el producto ya está en el catálogo; si es nuevo, el formulario lo pide. El **plazo de entrega** se propone desde el texto "N a M días hábiles" (hoy + M días hábiles) y es editable.
- **Límites:** funciona con la plantilla de cotización de GyG. Si el formato cambia o el PDF es escaneado (sin texto), los campos no encontrados quedan vacíos con un aviso y se completan a mano.
- **Total:** se usa el **neto** (Subtotal, sin IVA), que coincide con Σ unidades × precio. El total con IVA se muestra como referencia. Si la suma de productos no cuadra con el subtotal, se avisa.
- **[VALIDAR] para el informe:** extiende RF-05 (registro de adjudicación) y RF-11 (foto en el catálogo). Agrega los campos `numero_cotizacion`, `fecha_cotizacion` y `foto_path`.
- Pruebas: `lector_test.ts` (fixture con las posiciones reales de la cotización 5609-132-COT26) y `cotizacion_importada_test.dart`. Se verificó de punta a punta con el PDF real: los 8 campos y la foto.

---

## 1. Qué pasó con el prototipo (`cotizaciones_rutas`)

| Elemento del prototipo | Decisión | Motivo |
|---|---|---|
| Supabase + Riverpod + go_router | **Se conserva** | Calza con el stack y la arquitectura por capas |
| Login con Supabase Auth, perfiles con rol y RLS | **Se conserva y se ajusta** | Base de RF-01/02. Tabla `profiles` → `usuario`, rol `admin` → `administrador` |
| Optimización de rutas en una Edge Function | **Se conserva la idea, se reescribe** | Ahora usa **Routes API** (el prototipo usaba Directions API, que no es la tecnología especificada) |
| Pantalla de mapa con marcadores y trazado | **Se conserva y se mejora** | Dibuja el trazado real de la ruta (polilínea) en vez de líneas rectas |
| Manejo de secretos (`env/`, `secrets.properties`, Codemagic) | **Se conserva** | Buena práctica (ISO/IEC 27001) |
| Extracción de PDF con **Google Gemini** | **Se elimina** | Tecnología fuera del stack cerrado (regla 5) y función no especificada |
| Subida de PDF y foto del producto (Storage) | **Se elimina, y luego se reintroduce sin IA** | Pedido por el equipo (§0.1): lectura determinista de la plantilla de GyG; la foto va al catálogo |
| Registro público de cuentas | **Se elimina** | Exactamente 2 usuarios. Cualquiera podía crearse una cuenta |
| Tabla `cotizaciones` (un ítem, `monto` total) | **Se reemplaza** | No permitía calcular el margen neto (RF-06/07) |
| Estado en la **ruta** (pendiente/en_curso/completada) | **Se reemplaza** | La especificación exige estado por **despacho**: Pendiente → En Ruta → Entregado |
| Chofer leía `monto` y `precio_unidad`; el mapa le mostraba montos | **Se corrige** | Incumplía RF-03 (fuga de datos financieros) |
| Geocodificación con el paquete `geocoding` (del teléfono) | **Se reemplaza** | Ahora usa **Google Places API** en el servidor; además el paquete no funciona en web |

> La migración `20261112000000_gygtrack_modelo.sql` **borra** las tablas del prototipo
> y sus datos. Si el proyecto Supabase tiene datos que conservar, respaldarlos antes.

---

## 2. Estructura del código (arquitectura por capas)

```
lib/
  core/                         Transversal: configuración, router, formato, errores,
                                almacenamiento local, widgets comunes
  modulos/
    administracion_seguridad/   Módulo 4 — RF-01 a RF-04
    gestion_comercial/          Módulo 1 — RF-05 a RF-11
    logistico_notificaciones/   Módulo 2 — RF-12 a RF-20
    enrutamiento/               Módulo 3 — RF-21 a RF-24
      dominio/                  Capa de dominio: modelos y reglas de negocio puras
      datos/                    Capa de datos: repositorios (Supabase + almacenamiento local)
      presentacion/             Capa de presentación: pantallas y providers (Riverpod)
supabase/
  migrations/                   Esquema, RLS, vistas, triggers y CRON
  functions/                    Edge Functions (geocodificar, optimizar-ruta)
  pruebas/                      Pruebas de la base de datos sobre PostgreSQL (PGlite)
```

Hay exactamente **4 módulos**. La presentación solo habla con la capa de datos y el
dominio no depende de Flutter ni de Supabase, así que se puede probar de forma aislada.

---

## 3. Trazabilidad RF → implementación

| RF | Implementación |
|---|---|
| RF-01 | `LoginPantalla` + `AuthRepositorio.iniciarSesion` (Supabase Auth, correo y contraseña) |
| RF-02 | Columna `usuario.rol`, función `es_administrador()`, RLS y redirección por rol en `core/router.dart` |
| RF-03 | Las tablas con datos financieros son **solo del Administrador** (RLS). El Chofer lee únicamente las vistas `v_despacho_chofer`, `v_ruta_chofer` y `v_alerta_chofer`, que no tienen columnas financieras. Está probado en BD y en la copia local del teléfono |
| RF-04 | `cerrarSesion()`: cierra la sesión y borra los datos guardados en el dispositivo. Avisa si hay cambios sin sincronizar |
| RF-05 | `OrdenFormPantalla` → `orden_compra` + `detalle_orden`. **Importación automática desde el PDF de la cotización** (ver §0.1) |
| RF-06 | Costo y precio adjudicado **por línea** (`detalle_orden`). Toman por defecto los del catálogo |
| RF-07 | Trigger `detalle_orden_margen` → `orden_compra.margen_neto` (fuente oficial) + `calcularMargenNeto` en Dart, que lo muestra al instante mientras se escribe (KPI-03) |
| RF-08 | `UtilidadPanel`: indicadores y gráfico de barras de utilidad por orden |
| RF-09 | Crear, ver, editar y eliminar órdenes (`OrdenesRepositorio`) |
| RF-10 | `orden_compra.responsable_id` |
| RF-11 | `ProductosLista` (CRUD del catálogo) |
| RF-12 | `despacho.cantidad_bultos`, registrado desde el detalle de la orden |
| RF-13 | `ChoferInicioPantalla` y `DespachoChoferPantalla` (bultos, productos, cliente y dirección) |
| RF-14 | `EstadoDespacho` (Dart) + trigger `despacho_validar_transicion` (BD): solo se avanza de a un paso |
| RF-15 | `DespachosChoferRepositorio`: copia local + cola de cambios, sincronización automática al reconectar. RPC `cambiar_estado_despacho` idempotente |
| RF-16 | `despacho.fecha_hora_entrega` y `orden_compra.fecha_hora_entrega`, con la **hora real** del cambio aunque se sincronice después |
| RF-17 | `generar_alertas()`: alerta preventiva a 3 días del plazo |
| RF-18 | `generar_alertas()`: alerta "Día Cero" |
| RF-19 | Cada hora el CRON ejecuta `generar_alertas()` y luego `disparar_envio_push()`, que llama a la Edge Function `enviar-alertas` (pg_net). Esta envía cada alerta por **FCM** al responsable de la orden y a los Administradores, la marca `push_enviada` y limpia los tokens inválidos. La app registra el token en `dispositivo_push` al iniciar sesión y lo borra al cerrarla. Con la app abierta, la alerta se muestra en pantalla; al tocar la notificación se abre la lista de alertas. Push solo en la app móvil: en la web el Administrador ve las alertas en el panel |
| RF-20 | Tabla `alerta` + pantalla de alertas (Administrador: todas; Chofer: las suyas) |
| RF-21 | El Administrador elige los despachos de la jornada y `optimizar-ruta` compila sus direcciones. Las direcciones que aún no estaban validadas se geocodifican en ese momento (Places) y quedan guardadas en la orden |
| RF-22 | Edge Functions `optimizar-ruta` (**Routes API**) y `geocodificar` (**Places API**). La clave está solo en el servidor |
| RF-23 | `VistaRuta`: mapa con el trazado y las paradas en orden. El Chofer solo visualiza. **Ubicación del Chofer en tiempo real** (geolocator): punto en el mapa, precisión, "centrar en mí / seguir", próxima parada y distancia en línea recta. La ubicación no se envía ni se guarda en el servidor |
| RF-24 | `ruta.costo_ruta_sin_optimizar`, `costo_ruta_optimizada` y `ahorro` (columna calculada). `ruta.detalle_optimizacion` guarda la comparación **tiempo / km / TAG / combustible / costo** de la ruta sin optimizar, con TAG y sin TAG, más el motivo de la elección. Solo la ve el Administrador; el Chofer solo ve si la ruta usa TAG (sí/no) |

Indicadores: la vista `v_kpi` calcula KPI-01, 02, 04, 05, 06, 07 y 08 (solo Administrador).
KPI-03 se mide en la app (el margen aparece mientras se escribe).

---

## 4. Decisiones tomadas donde la especificación no decía nada [VALIDAR]

### 4.1 Campos agregados al modelo (marcados `-- [IMPL]` en la migración)

| Entidad.campo | Por qué |
|---|---|
| `orden_compra.numero_oc` | Identificador de la OC en Mercado Público (opcional) |
| `orden_compra.direccion_entrega`, `direccion_lat`, `direccion_lng` | Sin dirección y coordenadas no se puede cumplir RF-21/22 |
| `detalle_orden.costo_compra`, `precio_venta` | El precio adjudicado cambia en cada licitación. Copiarlo a la línea evita que un cambio de catálogo altere el margen de órdenes antiguas |
| `despacho.confirmado_en_app` | Necesario para medir KPI-07 |
| `alerta.push_enviada` | Seguimiento de RF-19 |
| Tabla `dispositivo_push` (token, usuario, plataforma) | Saber a qué teléfonos enviar cada alerta (RF-19) |
| `ruta.fecha`, `origen_*`, `distancia_km`, `duracion_min`, `polilinea`, `usa_peajes` | Jornada, bodega de salida y datos para mostrar la ruta |
| Tabla `ruta_parada` | Relación Ruta–Despacho con el orden de visita |

### 4.2 Reglas interpretadas

1. **Un despacho por orden**, creado automáticamente en estado Pendiente.
2. **Qué ve el Chofer:** los despachos de las órdenes donde es **responsable** y los de las **rutas que tiene asignadas**.
3. **Alerta preventiva:** se emite cuando faltan **entre 1 y 3 días** (normalmente a los 3). Así no se quedan sin alerta las órdenes registradas con menos de 3 días de plazo (KPI-06). Las órdenes ya entregadas no generan alertas. El CRON corre **cada hora** y es idempotente. "Hoy" se calcula en hora de Chile.
4. **Ruta "sin optimizar"** (línea base del ahorro): las mismas paradas ordenadas por plazo, que es como se arman hoy los repartos.
5. **Regla de $500 por cada 10 min:** se calcula la ruta optimizada **con peajes** y **sin peajes**. La más rápida se acepta solo si su costo adicional es menor a $500 × (minutos ahorrados / 10). Si además es más barata, se elige siempre.
6. **Costo de una ruta** = km ÷ 9 km/L × $1.272/L + peajes (TAG, estimación de Routes API).
7. **Viaje redondo:** la ruta sale de la bodega y vuelve a ella.
8. **"Optimizar según plazos" — el plazo manda sobre la distancia** (decisión del equipo, 2026-11-12): primero se cumple el plazo y después se optimiza.
   - Las paradas cuyo plazo vence en la jornada, o que ya vencieron, se visitan **antes** que el resto, aunque el recorrido total resulte más largo.
   - Dentro de cada grupo, Routes API ordena las paradas por distancia. Entre las rutas que respetan esa prioridad (con y sin peajes) se aplica la regla de $500 por cada 10 minutos.
   - Si se incluye un pedido con el plazo ya vencido, el Administrador recibe una advertencia.
   - Límite: como el plazo es una fecha (no una hora), no se puede verificar la hora exacta de llegada; se garantiza el **orden de visita**. Probado en `costos_test.ts` (`separarPorPlazo`).
9. **Cuentas:** no hay registro público. El Administrador crea las cuentas en Supabase Auth y toda cuenta nueva nace como Chofer.
10. **Cambios offline rechazados:** si el servidor rechaza un cambio de la cola (por ejemplo, porque el despacho se reasignó), se descarta y se avisa al Chofer.

### 4.3 Librerías nuevas (no son tecnologías de stack)

- `shared_preferences`: copia local de los datos del Chofer y cola offline (RF-15).
- `connectivity_plus`: detecta cuando vuelve la conexión para sincronizar (RF-15).
- `flutter_localizations`: textos del sistema en español.
- `firebase_core` y `firebase_messaging`: recepción de push vía FCM (ver §0).
- `geolocator`: ubicación del Chofer en tiempo real en el mapa de su ruta (RF-23).
- `file_picker`: elegir el PDF de la cotización (§0.1).

### 4.4 Destinatarios y reglas del push

11. Cada alerta se envía al **responsable de la orden** y a **todos los Administradores** que tengan la app instalada en el teléfono.
12. Una alerta se marca como enviada si llegó al menos a un dispositivo. Si nadie tiene un teléfono registrado, se reintenta en cada ejecución del CRON durante 36 horas y después se descarta, para no enviar avisos ya desfasados. La alerta igual queda registrada y visible en la app (RF-20).
13. El mensaje push no incluye datos financieros: solo cliente, número de OC y fecha de plazo.

---

## 5. Pruebas

| Qué | Cómo | Resultado |
|---|---|---|
| Reglas de dominio (margen, estados, formatos, polilínea, días hábiles, importación) y lógica offline | `flutter test` | 22 pruebas OK |
| Migraciones, RLS, vistas, triggers, RPC, alertas, KPI, registro de dispositivos y disparo push, respaldo y restauración del prototipo | `cd supabase/pruebas && npm install && npm test` (PostgreSQL real en PGlite) | 57 verificaciones OK |
| Regla de $500 por cada 10 min, costo de ruta, prioridad por plazo, texto de las alertas push, firma OAuth (RS256), respuestas de FCM y lector de cotizaciones, resumen y motivo de la optimización | Incluido en `npm test` | 22 pruebas OK |

---

## 6. Pendiente

1. **Respaldar y desplegar** en el proyecto Supabase (README §1 y §2). El respaldo se hace con `supabase/respaldo` y exige la cadena de conexión de la base, que no está en el repo.
2. **Crear el proyecto Firebase** y cargar sus claves (README §4). Sin eso, la app funciona, pero no envía push.
3. **Actualizar el informe:** agregar FCM al stack (§0) y la regla de prioridad por plazo (§4.2 punto 8).
4. Migrar de `package:flutter/material.dart` a `material_ui` (aviso de deprecación de Flutter 3.47+; no afecta el funcionamiento).
