# Manual de Usuario — GyGTrack

**GyG Comercial · Gestión Comercial y Trazabilidad Logística**

Este manual explica, paso a paso, cómo usar GyGTrack. Está dividido en dos partes
según el perfil de cada persona: **Administrador** (panel web) y **Chofer**
(aplicación móvil).

---

## 1. ¿Qué es GyGTrack?

GyGTrack es una aplicación para controlar los despachos de GyG Comercial a los
organismos del Estado (Mercado Público / ChileCompra). Permite:

- Registrar las órdenes adjudicadas y ver su **rentabilidad** (margen) al instante.
- **Avisar con anticipación** cuando una entrega está por vencer, para evitar multas.
- Armar la **ruta de reparto más conveniente** del día (tiempo, kilómetros y peajes TAG).
- Que el Chofer vea sus entregas, se guíe por el mapa y confirme cada despacho,
  incluso **sin conexión a internet**.

### Perfiles

| Perfil | Dónde la usa | Qué puede hacer |
|---|---|---|
| **Administrador** | Panel web (computador) | Todo: órdenes, productos, rentabilidad, rutas y alertas. |
| **Chofer** | Aplicación en el teléfono (Android) | Ver sus despachos y rutas, guiarse por el mapa y marcar las entregas. **No ve precios, costos ni márgenes.** |

---

## 2. Antes de empezar

- **Administrador:** necesita un computador con un navegador web (Google Chrome
  recomendado) y conexión a internet.
- **Chofer:** necesita el teléfono Android con la aplicación GyGTrack instalada.
  Para el mapa y la navegación conviene tener los **datos móviles** y el **GPS/ubicación**
  activados.
- **Cuentas:** las cuentas (correo y contraseña) las crea el Administrador. **No hay
  registro público:** nadie puede crear su propia cuenta desde la aplicación.

---

## 3. Iniciar sesión

Tanto el panel web como la app móvil parten en la misma pantalla de ingreso.

1. Escribe tu **Correo**.
2. Escribe tu **Contraseña**.
3. Presiona **Ingresar**.

El sistema te lleva automáticamente a la pantalla que corresponde a tu perfil
(panel del Administrador o "Mi jornada" del Chofer).

> Si olvidaste la contraseña o no puedes ingresar, pídele al Administrador que la
> restablezca.

Para **cerrar sesión**, usa el botón de salida (ícono de puerta) en la esquina
superior de la pantalla.

---

# PARTE A — Manual del Administrador (panel web)

El panel tiene un menú con cinco secciones: **Órdenes, Utilidad, Productos, Rutas
y Alertas**.

## A.1 Productos (catálogo)

Aquí está la lista de productos con su **costo de compra** y su **precio de venta**.
Sirven de base para calcular el margen de cada orden.

- Para **agregar un producto**, usa el botón de **＋** y completa el nombre, el costo
  de compra y el precio de venta.
- Para **editar** uno existente, tócalo en la lista.

## A.2 Órdenes

La sección **Órdenes** lista las adjudicaciones registradas. Hay dos formas de crear
una orden.

### Opción 1: Subir una cotización (automático)

1. En **Órdenes**, presiona **Subir cotización**.
2. Elige el **archivo PDF** de la cotización de GyG Comercial.
3. El sistema lee el PDF y **rellena solo** los campos: fecha, solicitado por,
   dirección, número de cotización, descripción, unidades, precio unitario, total
   y la **foto de cada producto**.
4. Revisa que los datos estén correctos, ajusta lo que necesites y presiona
   **Guardar**.

> Si el PDF trae varios productos, se toma **una foto por producto**.

### Opción 2: Crear una orden a mano

1. En **Órdenes**, presiona el botón **＋ (Nueva orden)**.
2. Completa los datos del cliente: **cliente, dirección de entrega, fecha
   comprometida** y, si corresponde, el **número de OC** y el **responsable**.
3. Agrega las **líneas de producto** (producto, cantidad, costo y precio). Puedes
   elegir productos del catálogo o escribir uno nuevo.
4. Presiona **Guardar**.

### Detalle de la orden

Al tocar una orden ves su detalle, incluido el **margen neto**, que se calcula solo:

> **Margen = Σ ((precio de venta − costo de compra) × cantidad)** de cada línea.

Cada orden genera automáticamente un **despacho** en estado **Pendiente**, que es lo
que después verá el Chofer.

## A.3 Utilidad (rentabilidad)

Muestra indicadores del negocio y el margen por orden:

- **Utilidad neta total**
- **Venta adjudicada**
- **Margen promedio** (%)
- **Órdenes** (cantidad)
- Un gráfico de **utilidad por orden** (de la más reciente a la más antigua).

## A.4 Rutas

Aquí se arman las rutas de reparto y se ve el ahorro estimado.

### Crear una ruta optimizada

1. En **Rutas**, presiona **Nueva ruta**.
2. Escribe la **dirección de salida (bodega)** y presiona **validar** para ubicarla
   en el mapa.
3. Define la **hora de salida de bodega** (si no la cambias, queda en 09:00). La
   hora influye en el costo de los peajes TAG (tarifa normal, punta o saturación).
4. Elige el o los **choferes**. Si eliges más de uno, el sistema reparte los
   despachos entre ellos y crea una ruta para cada uno.
5. Marca los **despachos** que entran en la ruta.
6. Presiona **Calcular ruta óptima**.

> **Regla del plazo:** lo que vence en la jornada se visita primero; después se
> optimiza el resto.

### Comparar y elegir la optimización

El detalle de la ruta muestra una comparación de tres alternativas —**Orden por
plazo**, **Optimizada permite TAG** y **Optimizada evita TAG**— con su **tiempo,
distancia, peajes (TAG), combustible y costo total**.

En **Optimizar por** puedes elegir el criterio:

- **Recomendada (equilibrada):** la que sugiere el sistema. Equilibra tiempo y dinero
  (acepta pagar más solo si ahorra al menos 10 minutos por cada $500).
- **Menos tiempo**
- **Menos plata** (combustible + TAG)
- **Menos km**

Al elegir un criterio, la ruta se actualiza completa (trazado del mapa, orden de las
paradas, kilómetros, minutos, TAG y ahorro).

> No se puede cambiar la optimización si la ruta **ya comenzó** (si algún despacho
> dejó de estar "Pendiente").

### TAG estimado

En **TAG estimado** se despliega cada pórtico o peaje que cruza la ruta, con su
concesión, la hora estimada de paso, el tipo de tarifa y el monto. El cálculo usa la
ubicación real de los pórticos y las **tarifas MOP 2026**.

### Asignar o cambiar el chofer

Si creaste una ruta **sin chofer**, ábrela y usa el botón **Asignar** (arriba, en la
tarjeta del chofer). Si ya tiene chofer, el botón dice **Cambiar**. Al asignarlo, la
ruta aparece en "Mi jornada" de ese chofer.

### Eliminar una ruta

Con el ícono de **basurero** (arriba a la derecha). Se borra solo la ruta; los
despachos no se modifican.

## A.5 Alertas

Lista las alertas de plazo de las órdenes (ver la sección 5 de este manual).

---

# PARTE B — Manual del Chofer (aplicación móvil)

> **Privacidad:** el Chofer **nunca** ve precios, costos, márgenes ni ahorros. Solo
> ve lo necesario para repartir.

## B.1 Mi jornada

Es la pantalla de inicio. Muestra tus despachos **organizados por ruta**:

- Las **rutas activas** con sus paradas.
- Los **despachos sin ruta** asignada.
- Las **rutas completadas** (agrupadas al final).

Arriba, un aviso indica si estás **sin conexión** y cuántos cambios quedan por
sincronizar.

## B.2 Ver la ruta en el mapa

Al abrir una ruta ves el **mapa** con:

- El **trazado** de la ruta y las **paradas numeradas** en orden.
- **Tu ubicación en tiempo real** (la primera vez, el teléfono pedirá permiso de
  ubicación: acéptalo).
- Botones para **centrar en toda la ruta**, **ver el tramo a la próxima parada** o
  **seguir tu ubicación**.

## B.3 Repartir: iniciar ruta y confirmar entregas

1. **Iniciar ruta:** presiona el botón **Iniciar ruta**. Se abre **Google Maps** una
   sola vez, con **todas las paradas en orden y el regreso a la bodega**. Usa la
   **dirección exacta** de cada orden.
2. Guíate con Google Maps hasta la primera parada.
3. Al entregar, vuelve a GyGTrack y presiona **Confirmar entrega**. Confirma en el
   aviso. La app te indica cuál es la siguiente parada (no abre otra pestaña).
4. Repite con cada parada.
5. **Navegar:** si cerraste Google Maps, el botón **Navegar** vuelve a abrir el
   recorrido que falta.
6. **Volver a bodega:** al terminar todas las entregas, el botón **Volver a bodega**
   abre la navegación de regreso.

> Google Maps admite hasta **10 puntos** por recorrido. Si la ruta tiene más paradas,
> la app te avisa y, al llegar a la décima, presionas **Navegar** para abrir el resto.

## B.4 Marcar "No entregado" (con justificación)

Si **no pudiste** entregar un despacho:

1. En la ruta o en el detalle del despacho, presiona **No entregado**.
2. Escribe el **motivo** (es **obligatorio**): por ejemplo "cliente ausente",
   "dirección incorrecta" o "local cerrado".
3. Presiona **Guardar**.

La parada queda marcada en **rojo** con su justificación y la ruta puede continuar.

**Reintentar:** si después logras entregarlo, abre ese despacho y usa **Reintentar
(volver a En Ruta)** o **Confirmar entrega**.

## B.5 Estados de un despacho

Un despacho pasa por estos estados:

**Pendiente → En Ruta → Entregado**, y además **En Ruta → No entregado** (con motivo),
desde donde puede volver a **En Ruta** o pasar a **Entregado**.

## B.6 Trabajo sin conexión

GyGTrack funciona **sin internet**:

- Tus despachos quedan guardados en el teléfono.
- Cuando marcas una entrega (o una no entrega), el cambio se guarda al tiro y queda
  **en espera**.
- Al recuperar la señal, los cambios se **sincronizan solos**, en orden y con la hora
  real en que los hiciste. Si algo queda pendiente, puedes presionar **Reintentar**.

## B.7 Alertas del Chofer

Desde el ícono de **campana** (arriba) ves las alertas de plazo de tus órdenes.

---

## 5. Alertas de plazo (para ambos perfiles)

GyGTrack avisa automáticamente para evitar multas por atraso:

- **Alerta preventiva:** **3 días antes** de la fecha comprometida.
- **Alerta "Día Cero":** el **mismo día** del vencimiento.

Las alertas quedan registradas en el sistema y se envían como **notificación push**
al teléfono del responsable.

---

## 6. Preguntas frecuentes y solución de problemas

**El mapa aparece en blanco o gris.**
Suele ser falta de conexión o que la clave del mapa aún se está activando. Revisa los
datos móviles, cierra y vuelve a abrir la app, o toca el botón de **"mi ubicación"**
para que el mapa se vuelva a cargar.

**No aparece mi ubicación en el mapa.**
Dale permiso de **ubicación** a la app (Ajustes del teléfono → Aplicaciones →
GyGTrack → Permisos → Ubicación) y activa el GPS.

**No me llegan las notificaciones.**
Verifica que la app tenga permiso de **notificaciones** en los ajustes del teléfono.

**No puedo iniciar sesión.**
Confirma el correo y la contraseña. Si persiste, pide al Administrador que revise tu
cuenta o restablezca la contraseña.

**Estoy sin internet.**
Puedes seguir trabajando: marca tus entregas igual; se guardan y se sincronizan al
recuperar la señal.

**No puedo cambiar la optimización de una ruta (Administrador).**
No se puede cambiar una ruta que **ya comenzó** (con despachos que dejaron de estar
"Pendiente"), ni una ruta creada antes de que existieran las alternativas: en ese
caso, elimínala y vuelve a calcularla.

---

## 7. Glosario

- **Despacho:** la entrega asociada a una orden. Pasa por los estados Pendiente, En
  Ruta, Entregado o No entregado.
- **Margen neto:** la ganancia estimada de una orden (ventas menos costos).
- **TAG:** cobro electrónico de las autopistas. El sistema estima su costo según la
  ruta y la hora.
- **Pórtico:** punto de cobro del TAG en la autopista.
- **Ruta optimizada:** el orden de visita de las paradas que mejor equilibra tiempo,
  kilómetros y peajes, respetando primero los plazos.
- **Offline / sin conexión:** modo en que la app funciona sin internet y sincroniza
  después.

---

*GyGTrack — Proyecto de Título, Ingeniería en Informática, INACAP.*
