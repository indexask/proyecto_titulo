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
| Foto de cada producto | `producto.foto_path` (bucket privado `productos` de Supabase Storage). Se toman **todas** las fotos de las páginas de "Detalles", ordenadas de arriba hacia abajo según su posición en la página, y se asignan a los productos en el mismo orden de la tabla. Si la cantidad no coincide, se avisa |

- **Sin IA y sin tecnologías nuevas.** La Edge Function `importar-cotizacion` lee la **plantilla propia de GyG** (etiquetas y columnas del PDF) con librerías de lectura de PDF, y extrae la foto embebida (JPEG). El PDF no sale de Supabase. Por eso no se reintroduce Gemini, que usaba el prototipo y está fuera del stack.
- **Lo que no viene en la cotización:** el **costo de compra** (necesario para el margen, RF-07) se completa solo si el producto ya está en el catálogo; si es nuevo, el formulario lo pide. El **plazo de entrega** se propone desde el texto "N a M días hábiles" (hoy + M días hábiles) y es editable.
- **Límites:** funciona con la plantilla de cotización de GyG. Si el formato cambia o el PDF es escaneado (sin texto), los campos no encontrados quedan vacíos con un aviso y se completan a mano.
- **Total:** se usa el **neto** (Subtotal, sin IVA), que coincide con Σ unidades × precio. El total con IVA se muestra como referencia. Si la suma de productos no cuadra con el subtotal, se avisa.
- **[VALIDAR] para el informe:** extiende RF-05 (registro de adjudicación) y RF-11 (foto en el catálogo). Agrega los campos `numero_cotizacion`, `fecha_cotizacion` y `foto_path`.
- Pruebas: `lector_test.ts` (fixture con las posiciones reales de la cotización 5609-132-COT26) y `cotizacion_importada_test.dart`. Se verificó de punta a punta con el PDF real: los 8 campos y la foto.


## 0.2 Motor de optimización: VRP + Route Matrix + Vecino Más Cercano + 2-opt (solicitud del equipo, 2026-11-13)

La optimización de rutas pasa de usar el optimizador interno de Google (`optimizeWaypointOrder`) a un **motor propio en tres capas**, implementado en la Edge Function `optimizar-ruta` (`vrp.ts`):

1. **Estructura del negocio (VRP, Vehicle Routing Problem).** El Administrador elige los despachos de la jornada y **uno o varios choferes**. El sistema reparte los despachos en un **lote por chofer** con un **barrido angular** desde la bodega: ordena las paradas por ángulo y prueba todos los cortes del círculo en lotes contiguos de tamaño equilibrado. Se queda con la partición de **menor costo total real**. Con un chofer, es una sola ruta.
2. **Datos del mundo real (Distance Matrix).** **Google Route Matrix**, parte de Routes API (sin tecnologías nuevas), entrega distancia, tiempo y peajes por calles entre la bodega y todas las paradas, con TAG y sin TAG. Costo de cada tramo = combustible (km ÷ 9 × $1.272) + peajes + **$50 por minuto**, que equivale a la regla de $500 por cada 10 minutos ahorrados.
3. **Motor algorítmico.** Cada lote se ordena con **Vecino Más Cercano** (heurística constructiva) y se mejora con **2-opt** (búsqueda local que invierte tramos para eliminar cruces). **El plazo manda:** lo que vence en la jornada va primero, y 2-opt solo reordena dentro de cada grupo.

Por cada lote se mantiene la comparación de 3 alternativas con el trazado real (orden por plazo, optimizada con TAG y optimizada sin TAG). La ruta detallada muestra el algoritmo, cuántas mejoras aplicó 2-opt y cuánto redujo el costo frente a usar solo Vecino Más Cercano.

**[VALIDAR] para el informe:**
- La especificación menciona **un** vehículo (JAC Sunray 2018). El VRP admite **varios choferes** con los mismos parámetros de vehículo.
- **No hay restricción de capacidad** (bultos por vehículo): la capacidad del furgón está **por definir**.
- Máximo **24 paradas por cálculo**, por el límite de 625 elementos de Route Matrix.
- **Costo de Google:** 2 matrices de (paradas + 1)² elementos por cálculo. Para 5 paradas son 72 elementos, un costo despreciable. Revisar la cuota gratuita mensual de Route Matrix si la cantidad de despachos crece.

Pruebas: `vrp_test.ts` (7): vecino más cercano, 2-opt elimina cruces, 2-opt nunca empeora en 30 casos aleatorios, prioridad por plazo, reparto VRP por zonas, un chofer y más choferes que paradas.


## 0.3 Costo TAG por geocercas de pórticos (solicitud del equipo, 2026-11-13)

Google Routes **no tiene tarifas de autopistas chilenas** (devolvía $0 incluso en rutas por Costanera Norte o Vespucio). Por eso el TAG se estima con un sistema propio:

1. **Pórticos en la base de datos (tabla `portico`, PostgreSQL/Supabase).** Hay **161 puntos de cobro**:
   - **114 pórticos urbanos de 8 concesiones:** Autopista Central, Costanera Norte, Vespucio Norte, Vespucio Sur, Túnel San Cristóbal, Américo Vespucio Oriente, Acceso Nororiente y Acceso Vial AMB.
   - **47 peajes interurbanos de los accesos a Santiago** (agregados el 2026-11-13 con los PDF que entregó el equipo). Abarcan 25 plazas o pórticos, con un punto por sentido de cobro:
     - **Autopista Los Libertadores:** Chacabuco, Las Canteras y San José.
     - **Ruta 68:** Lo Prado, Zapata y Troncal Sur.
     - **Ruta 78:** T1 a T10.
     - **Ruta 5 Sur:** Angostura, Río Maipo, Gabriela y Tocornal.
     - **Ruta 5 Norte:** Lo Marcoleta, Buenaventura, La Montaña, Lo Pinto, Lampa, Pichidangui y Túnel El Melón.
     - Las tarifas están en `supabase/datos/tag/tarifas_interurbanas_2026.json`, la ubicación en `osm_peajes_interurbanos.json` y la migración es `20261114000000_peajes_interurbanos.sql`.
     - Una plaza suele tener varios nodos en el mismo sentido (casetas y pórtico free flow). Se deja **uno por sentido** para no cobrar dos veces la pasada.
     - Las plazas que están en una calzada de doble sentido (Chacabuco y San José) cobran en ambos sentidos.
   - **Ubicación y sentido de cobro:** OpenStreetMap (`highway=toll_gantry` y la calzada de un sentido donde está cada pórtico), © colaboradores de OpenStreetMap, licencia ODbL.
   - **Tarifas y horarios:** PDF oficiales **MOP / DGC "Peajes Tarifas 2026"** entregados por el equipo, transcritos en `supabase/datos/tag/tarifas_2026.json`.
   - La migración se genera con `supabase/datos/tag/generar_porticos.mjs`, que empareja cada pórtico con su tarifa por concesión, código y tramo; en Costanera Norte el mismo código cobra distinto según el sentido. Para actualizar las tarifas de un año nuevo se edita el JSON y se vuelve a generar.
2. **Ruta:** la polilínea real de cada alternativa (Routes API).
3. **Intersección:** la ruta cruza un pórtico si pasa a **menos de 35 m y en el mismo sentido** (±60°). Verificado con los 161 puntos reales: cada uno se detecta en su calzada, nunca se cobra el de la calzada contraria y ninguna plaza se cobra dos veces.
4. **Cálculo dinámico:** hora de paso = **hora de salida** (nuevo campo, por defecto 09:00) + tiempo proporcional a la distancia recorrida. Se aplica la tarifa **TBFP / TBP / TS** del pórtico según el día (laboral, sábado o domingo) y la hora. Américo Vespucio Oriente cobra **por km** entre el primer y el último pórtico de la pasada.

El TAG estimado entra al costo de cada alternativa (con y sin TAG, y el orden por plazo) y a la regla de $500 por cada 10 minutos. El detalle de la ruta muestra cada pórtico con su hora, tarifa y monto.

**[VALIDAR] para el informe:**
- **Categoría del vehículo:** se usa la **Categoría 1** (autos y camionetas) para el JAC Sunray 2018. Si las concesionarias lo clasifican como Categoría 2 (buses y camiones), los montos se duplican (constante `CATEGORIA_TAG`).
- Las ventanas horarias se transcribieron de las tablas de los PDF. Sábados, domingos y festivos usan TBFP, salvo los pórticos con ventanas propias (Autopista Central y Túnel San Cristóbal). Los festivos no se distinguen.
- La hora de paso no incluye el tiempo detenido en cada entrega.
- Acceso Nororiente usa la tarifa normal, porque su horario punta no figura en el PDF.
- **Peajes interurbanos:**
  - **Ruta 68 (Lo Prado, Zapata) y Ruta 5 Norte (Lo Marcoleta a Lo Pinto):** los PDF traen tarifa punta pero no su horario. Se estiman con la tarifa normal.
  - **Ruta 78:** la tarifa punta solo rige en temporada alta (20 de diciembre a 10 de marzo) y en fines de semana largos, así que tampoco se modela.
  - **Las Canteras y San José:** usan la columna "Las Canteras / San José" ($1.400 con TAG). El PDF da $2.800 para la troncal Las Canteras, pero solo para usuarios sin TAG.
  - **Por definir:** las laterales que en OpenStreetMap no tienen nombre (Lateral Ruta 5 Sur, laterales de Ruta 68, San Luis/Chicureo), porque no se puede ubicar el punto de cobro con certeza.
- La matriz del motor VRP (Vecino Más Cercano + 2-opt) no incluye el TAG, porque Route Matrix no entrega trazados; el TAG se considera en la comparación final de alternativas.

Pruebas: `peajes_test.ts` (7): geocerca por sentido, radio de 35 m, TBFP/TBP/TS según hora, ida y vuelta, cobro por km. Verificación con los 161 puntos reales. La base comprueba que se cargan 161 puntos de 13 concesiones, que Angostura tiene un punto por sentido ($3.800 en categoría 1), que Chacabuco cobra en ambos sentidos y que el Chofer no puede leer la tabla.

---

## 0.4 Elegir el criterio de optimización (solicitud del equipo, 2026-11-13)

En el detalle de la ruta, el Administrador elige **Optimizar por**:
- **Recomendada (equilibrada):** es la que propone el sistema. Busca el menor costo más $50 por minuto, que equivale a la regla de $500 por cada 10 minutos.
- **Menos tiempo.**
- **Menos plata:** combustible más TAG.
- **Menos km.**

Cada criterio elige entre las 3 alternativas que ya calcula `optimizar-ruta`: orden por plazo, optimizada permitiendo TAG y optimizada evitando TAG. En empate gana la recomendada.

- **Datos:** `detalle_optimizacion.alternativas` guarda, por alternativa, el trazado, el orden de las paradas, si usa TAG, el desglose de pórticos y el resumen de tiempo, km y costo. También se guardan `recomendada`, `criterio` y `motivoRecomendada`.
- **Cambio atómico:** la función `elegir_alternativa_ruta` (migración `20261114000100`) actualiza en una sola operación el trazado, km, tiempo, TAG, el costo optimizado (y con él el ahorro) y el orden de `ruta_parada`.
  - Solo la puede usar el Administrador.
  - Se rechaza si algún despacho de la ruta ya salió de "pendiente". Así no se cambia el orden con el Chofer en camino.
- **Rutas antiguas:** las calculadas antes de este cambio no tienen las alternativas guardadas. Para cambiarlas hay que volver a calcularlas.
- **Ahorro:** si el Administrador elige una alternativa más cara que la ruta sin optimizar, el ahorro de KPI-08 puede quedar negativo. Eso es lo esperado.

Pruebas: `criterio_ruta_test.dart` (criterio → alternativa, empates, rutas antiguas). La base comprueba el cambio completo, que el Chofer no puede usarlo y el bloqueo cuando la ruta ya comenzó.

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
| RF-13 | Inicio del Chofer **"Mi jornada"** (`ChoferInicioPantalla`): despachos **organizados por ruta** (activas primero, con estado Por iniciar/En curso/Completada, avance "N de M entregadas" y paradas en orden de visita), luego **despachos sin ruta asignada** y al final el historial de rutas completadas. `DespachoChoferPantalla`: bultos, productos, cliente y dirección |
| RF-14 | `EstadoDespacho` (Dart) + trigger `despacho_validar_transicion` (BD): solo se avanza de a un paso |
| RF-15 | `DespachosChoferRepositorio`: copia local + cola de cambios, sincronización automática al reconectar. RPC `cambiar_estado_despacho` idempotente |
| RF-16 | `despacho.fecha_hora_entrega` y `orden_compra.fecha_hora_entrega`, con la **hora real** del cambio aunque se sincronice después |
| RF-17 | `generar_alertas()`: alerta preventiva a 3 días del plazo |
| RF-18 | `generar_alertas()`: alerta "Día Cero" |
| RF-19 | Cada hora el CRON ejecuta `generar_alertas()` y luego `disparar_envio_push()`, que llama a la Edge Function `enviar-alertas` (pg_net). Esta envía cada alerta por **FCM** al responsable de la orden y a los Administradores, la marca `push_enviada` y limpia los tokens inválidos. La app registra el token en `dispositivo_push` al iniciar sesión y lo borra al cerrarla. Con la app abierta, la alerta se muestra en pantalla; al tocar la notificación se abre la lista de alertas. Push solo en la app móvil: en la web el Administrador ve las alertas en el panel |
| RF-20 | Tabla `alerta` + pantalla de alertas (Administrador: todas; Chofer: las suyas) |
| RF-21 | El Administrador elige los despachos de la jornada y `optimizar-ruta` compila sus direcciones. Las direcciones que aún no estaban validadas se geocodifican en ese momento (Places) y quedan guardadas en la orden. Si la ruta se creó sin chofer, el Administrador puede **asignarlo o cambiarlo después** desde el detalle de la ruta (`ruta.chofer_id`); la ruta aparece entonces en "Mi jornada" de ese Chofer |
| RF-22 | Edge Functions `optimizar-ruta` (**Routes API**) y `geocodificar` (**Places API**). La clave está solo en el servidor |
| RF-23 | `VistaRuta`: mapa con el trazado y las paradas en orden. El Chofer solo visualiza. **Ubicación del Chofer en tiempo real** (geolocator): punto en el mapa, precisión, "centrar en mí / seguir", próxima parada y distancia en línea recta. La ubicación no se envía ni se guarda en el servidor. **Flujo en ruta:** "Iniciar ruta" (pendientes → En Ruta) abre **una sola vez** Google Maps con **todo el recorrido**: las paradas en orden como puntos intermedios y el regreso a bodega como destino. Se usa la **dirección exacta** de cada orden, porque con coordenadas Google Maps rotula el destino con el lugar más cercano, por ejemplo "Universidad de Chile" en vez de la calle. Google Maps admite 10 puntos por recorrido; si hay más paradas, se avisa y "Navegar" abre el resto. "Confirmar entrega" ya no abre pestañas nuevas. "Navegar" vuelve a abrir lo que falta, y al final está "Volver a bodega". Se usan enlaces de Google Maps (sin costo ni clave). No se modifica la ruta. Cámara con tres modos: tramo actual (ubicación → próxima parada), ruta completa y seguirme |
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
5. **Regla de $500 por cada 10 min** (**confirmada por el equipo el 2026-11-13: se mantiene para valorar el tiempo del chofer**; por eso una ruta puede costar más en dinero si ahorra tiempo suficiente, y el ahorro de KPI-08 puede ser negativo en esas rutas): se comparan **tres** alternativas que respetan el plazo: el **orden por plazo** (sin optimizar), la **optimizada permitiendo TAG** y la **optimizada evitando TAG**. "Aceptar un costo adicional menor a $500 por cada 10 minutos ahorrados" equivale a elegir la de menor **costo + $50 por minuto**; en empate gana la más lenta. Hace falta comparar también el orden por plazo porque Google optimiza el orden por **tiempo**: en la prueba real del 12-11-2026 (Maipú → Providencia → La Reina), la ruta "optimizada" ahorraba 5 min pero recorría 5,4 km más (+$764). Como 5 min solo justifican $250, se mantuvo el orden por plazo. La tabla del Administrador muestra las tres alternativas y el motivo en palabras.
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
- `url_launcher`: abrir en Google Maps la navegación del recorrido completo (RF-23).

### 4.4 Destinatarios y reglas del push

11. Cada alerta se envía al **responsable de la orden** y a **todos los Administradores** que tengan la app instalada en el teléfono.
12. Una alerta se marca como enviada si llegó al menos a un dispositivo. Si nadie tiene un teléfono registrado, se reintenta en cada ejecución del CRON durante 36 horas y después se descarta, para no enviar avisos ya desfasados. La alerta igual queda registrada y visible en la app (RF-20).
13. El mensaje push no incluye datos financieros: solo cliente, número de OC y fecha de plazo.

---

## 5. Pruebas

| Qué | Cómo | Resultado |
|---|---|---|
| Reglas de dominio (margen, estados, formatos, polilínea, días hábiles, importación) y lógica offline | `flutter test` | 28 pruebas OK |
| Migraciones, RLS, vistas, triggers, RPC, alertas, KPI, registro de dispositivos y disparo push, respaldo y restauración del prototipo | `cd supabase/pruebas && npm install && npm test` (PostgreSQL real en PGlite) | 57 verificaciones OK |
| Regla de $500 por cada 10 min, costo de ruta, prioridad por plazo, texto de las alertas push, firma OAuth (RS256), respuestas de FCM y lector de cotizaciones (incluidas varias fotos por posición), resumen, elección entre 3 alternativas, motivo de la optimización, motor VRP + Vecino Más Cercano + 2-opt y TAG por geocercas | Incluido en `npm test` | 41 pruebas OK |

---

## 6. Pendiente

1. **Respaldar y desplegar** en el proyecto Supabase (README §1 y §2). El respaldo se hace con `supabase/respaldo` y exige la cadena de conexión de la base, que no está en el repo.
2. **Crear el proyecto Firebase** y cargar sus claves (README §4). Sin eso, la app funciona, pero no envía push.
3. **Actualizar el informe:** agregar FCM al stack (§0) y la regla de prioridad por plazo (§4.2 punto 8).
4. Migrar de `package:flutter/material.dart` a `material_ui` (aviso de deprecación de Flutter 3.47+; no afecta el funcionamiento).
