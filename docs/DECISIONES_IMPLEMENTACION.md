# GyGTrack — Decisiones de implementación y trazabilidad

Documento de apoyo a la **Regla de Espejo** (informe ↔ aplicación). Registra qué
se conservó del prototipo, qué se cambió y por qué, cada decisión tomada donde
la especificación no decía nada, y lo que queda pendiente. Todo lo marcado como
**[VALIDAR]** debe contrastarse con el ER de la Parte 2 o confirmarse con el equipo
antes de reflejarlo en el informe.

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
| Subida de PDF y foto del producto (Storage) | **Se elimina** | No forma parte de los RF |
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
| RF-05 | `OrdenFormPantalla` → `orden_compra` + `detalle_orden` |
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
| RF-19 | **PENDIENTE**: envío push (ver §6) |
| RF-20 | Tabla `alerta` + pantalla de alertas (Administrador: todas; Chofer: las suyas) |
| RF-21 | El Administrador elige los despachos de la jornada y `optimizar-ruta` compila sus direcciones |
| RF-22 | Edge Functions `optimizar-ruta` (**Routes API**) y `geocodificar` (**Places API**). La clave está solo en el servidor |
| RF-23 | `VistaRuta`: mapa con el trazado y las paradas en orden. El Chofer solo visualiza |
| RF-24 | `ruta.costo_ruta_sin_optimizar`, `costo_ruta_optimizada` y `ahorro` (columna calculada) |

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
8. **"Optimizar según plazos":** la optimización minimiza el recorrido. La prioridad estricta por plazo (por ejemplo, visitar primero lo que vence hoy) **no está implementada**: queda **por definir** con el equipo.
9. **Cuentas:** no hay registro público. El Administrador crea las cuentas en Supabase Auth y toda cuenta nueva nace como Chofer.
10. **Cambios offline rechazados:** si el servidor rechaza un cambio de la cola (por ejemplo, porque el despacho se reasignó), se descarta y se avisa al Chofer.

### 4.3 Librerías nuevas (no son tecnologías de stack)

- `shared_preferences`: copia local de los datos del Chofer y cola offline (RF-15).
- `connectivity_plus`: detecta cuando vuelve la conexión para sincronizar (RF-15).
- `flutter_localizations`: textos del sistema en español.

---

## 5. Pruebas

| Qué | Cómo | Resultado |
|---|---|---|
| Reglas de dominio (margen, estados, formatos, polilínea) y lógica offline | `flutter test` | 17 pruebas OK |
| Migraciones, RLS, vistas, triggers, RPC, alertas, KPI | `cd supabase/pruebas && npm install && npm test` (PostgreSQL real en PGlite) | 39 verificaciones OK |
| Regla de $500 por cada 10 min y costo de ruta | Incluido en `npm test` | 5 pruebas OK |

---

## 6. Pendiente

1. **RF-19 — Notificaciones push.** Las alertas se generan y se registran (RF-17, 18 y 20), y se ven en la app. Falta **enviarlas al teléfono**. Para eso hay que elegir el proveedor de push, que la especificación no define. Opción habitual en Flutter: Firebase Cloud Messaging (solo para push; la base de datos sigue en Supabase). **Decisión del equipo.**
2. Prioridad estricta por plazo al optimizar (§4.2 punto 8).
3. Desplegar en el proyecto Supabase (ver README).
4. Migrar de `package:flutter/material.dart` a `material_ui` (aviso de deprecación de Flutter 3.47+; no afecta el funcionamiento).
