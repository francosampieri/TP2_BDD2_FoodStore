# Plan de trabajo — TP Unidad 4: FNBC y Desnormalización Controlada

> Especificación completa para la implementación del TP de Unidad 4.
> No contiene SQL ejecutable ni modifica archivos existentes.
> Base de trabajo prevista: `foodstore_tp_u4` (copia de `foodstore_tp5`, PostgreSQL 17).
> Scripts: `sql/tp_fnbc_control_lote.sql` y `sql/tp_desnormalizacion_top_categorias.sql`.
> Documentación: `docs/tp_u4/`.

---

## Contexto y decisiones previas

| Decisión | Detalle |
|---|---|
| Base de trabajo | `foodstore_tp_u4`, creada como copia de `foodstore_tp5`. No tocar `foodstore`, `foodstore_tp2`, `foodstore_tp3` ni `foodstore_tp5`. |
| Artefactos separados | Todo el DDL/DML de U4 va en `sql/tp_u4_*.sql`; los objetos creados llevan prefijo `tp_u4_` para no colisionar. |
| Experiencia previa | `mv_tp5_facturacion_categoria_mes` ya existe en `foodstore_tp5` como antecedente de vista materializada. La de U4 resuelve un caso distinto: top 5 diario, no mensual. |

---

## Parte 1 — Análisis FNBC de `ControlLoteAlmacen`

### 1.1 Relación inicial

La relación literal de la consigna es:

```
ControlLoteAlmacen(LoteID, DepositoID, ResponsableControlID)
```

Clave primaria inicial según la consigna: `(LoteID, DepositoID)`.

No existe ninguna de estas entidades en el esquema actual de FoodStore.
El análisis FNBC se realiza sobre la relación como ejercicio académico;
el diseño SQL resultante se mapea a FoodStore en la sección 1.7.

---

### 1.2 Dependencias funcionales formales

```
DF1:  (LoteID, DepositoID) → ResponsableControlID
DF2:  ResponsableControlID → DepositoID
```

**Justificación semántica:**
- La combinación de un lote con un depósito determina quién es el responsable de
  control asignado a ese par.
- Un responsable de control trabaja en un único depósito; conocer el responsable
  es suficiente para saber el depósito.
- DF2 es la dependencia que genera la violación: `ResponsableControlID` no es
  superclave (no determina `LoteID`), pero sí determina `DepositoID`.

---

### 1.3 Clausuras y claves candidatas

**Clausura de `{LoteID, DepositoID}` (clave primaria declarada):**
```
{LoteID, DepositoID}+ = {LoteID, DepositoID, ResponsableControlID}
                                              (por DF1)
```
Determina todos los atributos → es clave candidata.

**Clausura de `{LoteID, ResponsableControlID}`:**
```
{LoteID, ResponsableControlID}+ = {LoteID, ResponsableControlID, DepositoID}
                                                                  (por DF2)
```
Determina todos los atributos → también es clave candidata.

**Clausura de `{LoteID}` solo:**
```
{LoteID}+ = {LoteID}
```
No determina `DepositoID` ni `ResponsableControlID` → no es clave candidata.

**Clausura de `{ResponsableControlID}` solo:**
```
{ResponsableControlID}+ = {ResponsableControlID, DepositoID}
                                                  (por DF2)
```
No determina `LoteID` → no es clave candidata.

**Claves candidatas de `ControlLoteAlmacen`:**
- `{LoteID, DepositoID}` — la clave primaria declarada en la consigna.
- `{LoteID, ResponsableControlID}` — segunda clave candidata derivada de DF2.

---

### 1.4 Atributos primos y no primos

| Atributo | Clasificación | Razón |
|---|---|---|
| `LoteID` | **Primo** | Pertenece a ambas claves candidatas |
| `DepositoID` | **Primo** | Pertenece a la clave candidata `{LoteID, DepositoID}` |
| `ResponsableControlID` | **Primo** | Pertenece a la clave candidata `{LoteID, ResponsableControlID}` |

Los **tres atributos son primos**. No existen atributos no primos en esta relación.

---

### 1.5 Diagnóstico formal de FNBC

**Definición:** una relación está en FNBC si y solo si para toda dependencia funcional
no trivial X → Y, X es superclave.

**Análisis de DF1: `{LoteID, DepositoID} → ResponsableControlID`**
- `{LoteID, DepositoID}` es superclave (es clave candidata).
- → No viola FNBC. ✓

**Análisis de DF2: `ResponsableControlID → DepositoID`**
- `{ResponsableControlID}` **no es superclave**: su clausura es
  `{ResponsableControlID, DepositoID}`, que no incluye `LoteID`.
- La dependencia es no trivial (`DepositoID` ∉ `{ResponsableControlID}`).
- → **Viola FNBC.**

**Diagnóstico:** `ControlLoteAlmacen` **no está en FNBC** por DF2.
Nótese que la relación **sí está en 3FN** (todos sus atributos son primos; la
condición de 3FN que prohíbe dependencias transitivas solo aplica a atributos
no primos). Este es el caso clásico donde 3FN no es suficiente: una relación puede
estar en 3FN y aun así violar FNBC cuando un atributo primo depende de un
determinante que no es superclave.

**Redundancia concreta:** si el mismo `ResponsableControlID = 801` aparece en los
lotes 501 y 502, el valor `DepositoID = 30` se almacena dos veces. Al actualizar
el depósito de un responsable habría que hacerlo en todas las filas donde aparece,
con riesgo de anomalías de actualización.

---

### 1.6 Descomposición sin pérdida en FNBC

Se extrae la dependencia violadora DF2 en una relación separada:

**R1 — Responsable por depósito:**
```
R1(ResponsableControlID, DepositoID)
    PK: ResponsableControlID
    Contiene DF2: ResponsableControlID → DepositoID
```

**R2 — Asignación de lote:**
```
R2(LoteID, ResponsableControlID)
    PK: (LoteID, ResponsableControlID)
    Contiene DF1 reformulada: (LoteID, ResponsableControlID) → [todos los atributos via R1]
```

**Verificación de lossless join (teorema de Heath):**
```
R1 ∩ R2 = {ResponsableControlID}
```
`ResponsableControlID` es la PK de R1 → la condición de Heath se cumple →
`R1 ⋈ R2 = ControlLoteAlmacen` sin filas espurias.

**Verificación sobre la instancia de ejemplo de la consigna:**

| LoteID | DepositoID | ResponsableControlID |
|---|---|---|
| 501 | 30 | 801 |
| 502 | 30 | 801 |
| 503 | 31 | 802 |

Después de la descomposición:

R1:

| ResponsableControlID | DepositoID |
|---|---|
| 801 | 30 |
| 802 | 31 |

R2:

| LoteID | ResponsableControlID |
|---|---|
| 501 | 801 |
| 502 | 801 |
| 503 | 802 |

`R1 ⋈ R2` reconstruye exactamente las tres filas originales. La redundancia de
`DepositoID = 30` desapareció de R2: ahora aparece una sola vez en R1.

**Preservación de dependencias:**
- DF2 (`ResponsableControlID → DepositoID`) está cubierta por R1. ✓
- DF1 (`(LoteID, DepositoID) → ResponsableControlID`) no está directamente en ninguna
  relación, pero puede verificarse vía join R1 ⋈ R2. Este es el costo conocido de
  la descomposición FNBC: puede no preservar todas las dependencias originales en
  una sola relación, pero sí las preserva en el esquema completo.

---

### 1.7 Diseño SQL adaptado a FoodStore

Las entidades `lote`, `deposito` y `responsable_control` no existen en FoodStore.
El mapeo crea entidades análogas con prefijo `tp_u4_`, usando `usuario.id_usuario`
como `ResponsableControlID` (tabla existente, no se modifica).

#### Decisiones de mapeo

| Concepto original | Equivalente FoodStore | Justificación |
|---|---|---|
| `DepositoID` | `tp_u4_deposito(id_deposito)` | Tabla maestra nueva, análoga a un depósito de almacenamiento |
| `LoteID` | `tp_u4_lote(id_lote)` | Tabla maestra nueva; en la relación R2 se combina con el responsable |
| `ResponsableControlID` | `usuario.id_usuario` | Tabla existente; no se modifica |

#### Tablas a crear en `sql/tp_fnbc_control_lote.sql`

**tp_u4_deposito** (entidad maestra, mínima):
```
tp_u4_deposito(
    id_deposito   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        VARCHAR(80) NOT NULL UNIQUE
)
```

**tp_u4_lote** (entidad maestra, mínima):
```
tp_u4_lote(
    id_lote   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    VARCHAR(80) NOT NULL UNIQUE
)
```

**tp_u4_r1_responsable_deposito** (R1 — responsable por depósito):
```
tp_u4_r1_responsable_deposito(
    id_usuario    BIGINT NOT NULL REFERENCES usuario(id_usuario),
    id_deposito   BIGINT NOT NULL REFERENCES tp_u4_deposito(id_deposito),
    PRIMARY KEY (id_usuario)        -- ResponsableControlID es PK de R1
)
```

**tp_u4_r2_lote_responsable** (R2 — asignación de lote):
```
tp_u4_r2_lote_responsable(
    id_lote       BIGINT NOT NULL REFERENCES tp_u4_lote(id_lote),
    id_usuario    BIGINT NOT NULL REFERENCES tp_u4_r1_responsable_deposito(id_usuario),
    PRIMARY KEY (id_lote, id_usuario)
)
```

La FK en R2 referencia la PK de R1 (`id_usuario`), garantizando que no puede
existir una asignación de lote para un responsable sin depósito registrado.

#### Vista de compatibilidad: relación original reconstituida

La vista reconstruye exactamente las tres columnas de `ControlLoteAlmacen`:

```
tp_u4_v_control_lote_almacen AS
SELECT
    r2.id_lote       AS lote_id,
    r1.id_deposito   AS deposito_id,
    r2.id_usuario    AS responsable_control_id
FROM tp_u4_r2_lote_responsable r2
JOIN tp_u4_r1_responsable_deposito r1
    ON r1.id_usuario = r2.id_usuario
```

Esta vista es el equivalente funcional de la relación original no-FNBC y permite
verificar el lossless join sobre los datos reales.

---

### 1.8 Instancia de ejemplo autocontenida

La instancia de ejemplo reproduce fielmente los tres valores de la consigna:

```
(501, 30, 801)
(502, 30, 801)
(503, 31, 802)
```

Dado que FoodStore usa `BIGINT GENERATED ALWAYS AS IDENTITY` para sus PKs,
los identificadores 501/502/503 (LoteID), 30/31 (DepositoID) y 801/802
(ResponsableControlID) **no pueden insertarse como valores literales** en columnas
de identidad. El script adopta la siguiente estrategia de cuatro pasos:

**Paso 1 — Crear y poblar la tabla original `control_lote_almacen`.**
La relación se crea como tabla normal con los IDs literales de la consigna,
independiente del esquema de identidad de FoodStore. Esto la hace autocontenida
y permite comparar directamente con la vista reconstruida:

```
control_lote_almacen(
    lote_id                INTEGER,    -- 501, 502, 503
    deposito_id            INTEGER,    -- 30, 31
    responsable_control_id INTEGER,    -- 801, 802
    PRIMARY KEY (lote_id, deposito_id)
)
```

Con las tres filas exactas de la consigna:

| lote_id | deposito_id | responsable_control_id |
|---|---|---|
| 501 | 30 | 801 |
| 502 | 30 | 801 |
| 503 | 31 | 802 |

**Paso 2 — Crear las tablas maestras (`tp_u4_deposito`, `tp_u4_lote`) y R1/R2.**
Estas tablas usan `IDENTITY` y recibirán IDs generados por la base (distintos de
30/31 y 501/502/503).

**Mapeo de IDs (correspondencia lógica con la consigna):**

| Valor consigna | Rol | Equivalente en `foodstore_tp_u4` |
|---|---|---|
| DepositoID 30 | Depósito A | `id_deposito` del INSERT con `nombre = 'Deposito A'` en `tp_u4_deposito` (valor real asignado por IDENTITY) |
| DepositoID 31 | Depósito B | `id_deposito` del INSERT con `nombre = 'Deposito B'` |
| ResponsableControlID 801 | Responsable 1 | `usuario.id_usuario = 1` (Admin Garcia, seed de `foodstore_tp_u4`) |
| ResponsableControlID 802 | Responsable 2 | `usuario.id_usuario = 2` (Ana Gomez, seed) |
| LoteID 501 | Lote 501 | `id_lote` del INSERT con `nombre = 'Lote 501'` en `tp_u4_lote` |
| LoteID 502 | Lote 502 | `id_lote` del INSERT con `nombre = 'Lote 502'` |
| LoteID 503 | Lote 503 | `id_lote` del INSERT con `nombre = 'Lote 503'` |

El script captura los IDs generados con CTEs + `RETURNING` y los usa en los
INSERTs de R1 y R2.

**Paso 3 — Migrar desde la tabla original.**
R1 y R2 se pueblan con `INSERT … SELECT` que lee `control_lote_almacen` y resuelve
la correspondencia con los IDs reales de FoodStore usando JOINs por nombre
(ej: `tp_u4_deposito.nombre = 'Deposito A'` para el DepositoID 30).

**Paso 4 — Vista de correspondencia para verificación visual.**
Una consulta final muestra las tres filas de `tp_u4_v_control_lote_almacen`
junto con las tres filas de `control_lote_almacen`, permitiendo confirmar que
la estructura lógica coincide con la instancia de la consigna.

> **Validación manual requerida en DBeaver:**
> Antes de ejecutar el script, confirmar que `id_usuario IN (1, 2)` existen y no
> están eliminados en `foodstore_tp_u4`. Si la copia fue limpia desde
> `foodstore_tp5`, el seed está presente.

---

### 1.9 Verificaciones de equivalencia entre tabla original y vista reconstruida

La auditoría EXCEPT compara `control_lote_almacen` (relación original con los IDs
literales de la consigna) contra `tp_u4_v_control_lote_almacen` (reconstruida desde
R1 y R2). Para que la comparación sea directa, la vista proyecta los IDs de la
consigna uniéndose con las tablas maestras y con `usuario` para resolver los valores
originales a partir de los nombres o del mapeo de usuarios del seed.

**Dirección A — filas en `control_lote_almacen` no presentes en la vista:**
```
SELECT lote_id, deposito_id, responsable_control_id
FROM   control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM   tp_u4_v_control_lote_almacen;
```
Resultado esperado: **0 filas**.

**Dirección B — filas en la vista no presentes en `control_lote_almacen`:**
```
SELECT lote_id, deposito_id, responsable_control_id
FROM   tp_u4_v_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM   control_lote_almacen;
```
Resultado esperado: **0 filas**.

> **Validación manual requerida en DBeaver:**
> Ejecutar ambas verificaciones EXCEPT después de completar los pasos 1–3.
> Si alguna devuelve filas, revisar la proyección de la vista o la migración.
> Documentar el resultado (0 filas en cada dirección) en el informe.

---

## Parte 2 — Top 5 diario de categorías por monto vendido

### 2.1 Consulta base adaptada al esquema real

La consulta calcula, para el día de la fecha, las 5 categorías con mayor facturación
según los detalles de pedido vigentes:

```sql
SELECT
    c.id_categoria,
    c.nombre_categoria,
    SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido         ped ON ped.id_pedido  = dp.id_pedido
                          AND ped.eliminado  = FALSE
                          AND ped.fecha      = CURRENT_DATE
JOIN   producto       pr  ON pr.id_producto = dp.id_producto
JOIN   categoria      c   ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria
ORDER  BY monto_vendido DESC
LIMIT  5;
```

**Notas de diseño:**
- El filtro `ped.fecha = CURRENT_DATE` es el predicado selectivo que restringe el
  análisis al día en curso.
- Se agrupa por `c.id_categoria, c.nombre_categoria` (no solo por id) para poder
  proyectar el nombre sin subconsulta adicional.
- El `LIMIT 5` forma parte de la semántica del reporte, no de la vista materializada
  (ver sección 2.3).

---

### 2.2 Elección del patrón: vista materializada

**Por qué vista materializada y no vista regular:**

Una vista regular re-ejecuta la consulta completa en cada SELECT. Con datos de producción
(carga similar a `foodstore_tp5`: 400.000+ detalles), el plan involucra cuatro joins y
una agregación completa sobre `detalle_pedido` filtrada por fecha — patrón idéntico al de
facturación mensual del TP5, que medía ~946 ms en TP4 y ~706 ms en TP5. Una vista
regular repetiría ese costo en cada consulta.

**Por qué no una tabla de caché manual:**
Una tabla de caché requiere lógica de inserción/actualización/truncado gestionada
explícitamente. Una vista materializada delega esa lógica al motor con
`REFRESH MATERIALIZED VIEW`, con semántica bien definida y soporte nativo de
`CONCURRENTLY` para no bloquear lecturas.

**Justificación de la elección:**
La vista materializada es el patrón de desnormalización controlada adecuado para este
reporte porque:
- Precomputa los joins y la agregación una sola vez por `REFRESH`.
- Cada lectura posterior accede a una tabla pequeña (máximo una fila por categoría
  con ventas en el día) en lugar de repetir el scan completo de `detalle_pedido`.
- El `REFRESH` frecuente (por ejemplo, cada hora durante el horario operativo) es el
  mecanismo controlado y documentado para mantener el dato actualizado.
- Es el mismo patrón verificado con medición real en `informe_mediciones_tp5.md`
  (706 ms → 0.284 ms).

**Límite explícito — instantánea del último REFRESH:**
La vista materializada muestra el estado de los datos en el momento exacto en que se
ejecutó el último `REFRESH`. Los pedidos ingresados después de ese momento no aparecen
en la vista hasta el próximo `REFRESH`. Esto implica una posible desactualización entre
refrescos que debe documentarse en el informe: el reporte puede no reflejar el top 5
exacto del momento de la consulta, sino el del último refresh ejecutado. Por esta razón
la vista no debe usarse para operaciones transaccionales ni para calcular totales de
pedidos activos; esas operaciones deben ir contra las tablas base.

---

### 2.3 Definición de la vista materializada

**Nombre:** `mv_tp_u4_top5_cat_dia`

**Lógica de la vista (sin ORDER BY ni LIMIT en la definición):**

La vista materializa la agregación completa por categoría para el día de la fecha,
sin el `LIMIT 5`. El límite se aplica al consultar la vista.

```
Tablas:   detalle_pedido JOIN pedido JOIN producto JOIN categoria
Filtros:  detalle_pedido.eliminado = FALSE
          pedido.eliminado = FALSE
          pedido.fecha = CURRENT_DATE   ← capturado en el momento del REFRESH
Agrupación: categoria.id_categoria, categoria.nombre_categoria
Agregado: SUM(detalle_pedido.subtotal) AS monto_vendido
```

> **Decisión de diseño importante:** `CURRENT_DATE` en la definición de la vista
> se evalúa en el momento del `REFRESH`, no en el momento de la lectura. Una vista
> materializada con `WITH DATA` toma una foto del resultado en el instante del refresh.
> Esto significa que si el `REFRESH` se ejecutó ayer, la vista muestra datos de ayer.
> Este comportamiento debe documentarse explícitamente en el informe.

**Columnas de la vista:**

| Columna | Expresión | Tipo |
|---|---|---|
| `id_categoria` | `categoria.id_categoria` | `BIGINT` |
| `nombre_categoria` | `categoria.nombre_categoria` | `VARCHAR(80)` |
| `monto_vendido` | `SUM(detalle_pedido.subtotal)` | `NUMERIC(12,2)` |

---

### 2.4 Índice único para REFRESH CONCURRENTLY

La combinación `(id_categoria)` identifica unívocamente cada fila del resultado
(la agrupación produce exactamente una fila por categoría activa con ventas en el día).

**Índice:**
```
CREATE UNIQUE INDEX uq_mv_tp_u4_top5_cat_dia
ON mv_tp_u4_top5_cat_dia (id_categoria);
```

**Cuándo crearlo:** después del primer `REFRESH MATERIALIZED VIEW mv_tp_u4_top5_cat_dia`
(que pobla la vista con `WITH DATA`). El índice es requisito para poder ejecutar
`REFRESH MATERIALIZED VIEW CONCURRENTLY` en refrescos posteriores sin bloquear lecturas.

> **Validación manual requerida en DBeaver:**
> Confirmar que el primer `REFRESH` produjo filas (puede ser 0 si no hay pedidos
> del día en `foodstore_tp_u4`). Si es 0 filas, crear un pedido de prueba con fecha
> `CURRENT_DATE` antes del refresh, o ajustar el filtro a una fecha con datos.

---

### 2.5 Estrategia de REFRESH

| Situación | Comando recomendado |
|---|---|
| Primer populate (antes del índice único) | `REFRESH MATERIALIZED VIEW mv_tp_u4_top5_cat_dia;` |
| Refrescos posteriores (con índice único creado) | `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tp_u4_top5_cat_dia;` |
| Entorno de demo/TP con usuarios concurrentes | `CONCURRENTLY` para no bloquear lecturas |
| Entorno de desarrollo sin concurrencia | Ambas formas son equivalentes |

**Frecuencia sugerida:** una vez por hora durante el horario operativo del negocio,
o manualmente antes de cada consulta del reporte diario. No por cada INSERT en
`detalle_pedido` (el costo de re-ejecutar los cuatro joins supera el beneficio).

---

### 2.6 Consulta de lectura sobre la vista

```sql
SELECT id_categoria,
       nombre_categoria,
       monto_vendido
FROM   mv_tp_u4_top5_cat_dia
ORDER  BY monto_vendido DESC
LIMIT  5;
```

Esta consulta lee solo las filas materializadas (máximo una por categoría con ventas
en el día, tipicamente 5–6 filas) y aplica el `LIMIT 5` al resultado ya reducido.

---

### 2.7 Auditoría de equivalencia con EXCEPT bidireccional

Las dos verificaciones comprueban que la vista materializa exactamente el mismo
resultado que la consulta directa equivalente (sin `LIMIT`):

**Dirección A — filas en la consulta directa no presentes en la vista:**
```sql
-- Consulta directa equivalente (sin LIMIT)
SELECT c.id_categoria, c.nombre_categoria, SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido ped ON ped.id_pedido = dp.id_pedido
                 AND ped.eliminado  = FALSE
                 AND ped.fecha      = CURRENT_DATE
JOIN   producto pr ON pr.id_producto = dp.id_producto
JOIN   categoria c ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria

EXCEPT

SELECT id_categoria, nombre_categoria, monto_vendido
FROM   mv_tp_u4_top5_cat_dia;
```
Resultado esperado: **0 filas**.

**Dirección B — filas en la vista no presentes en la consulta directa:**
```sql
SELECT id_categoria, nombre_categoria, monto_vendido
FROM   mv_tp_u4_top5_cat_dia

EXCEPT

SELECT c.id_categoria, c.nombre_categoria, SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido ped ON ped.id_pedido = dp.id_pedido
                 AND ped.eliminado  = FALSE
                 AND ped.fecha      = CURRENT_DATE
JOIN   producto pr ON pr.id_producto = dp.id_producto
JOIN   categoria c ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria;
```
Resultado esperado: **0 filas**.

> **Validación manual requerida en DBeaver:**
> Ejecutar las dos verificaciones EXCEPT inmediatamente después del `REFRESH`
> y antes de insertar nuevos datos. Si alguna devuelve filas, la definición
> de la vista tiene una discrepancia con la consulta directa y debe corregirse.
> Documentar ambos resultados en el informe.

---

### 2.8 Medición con EXPLAIN ANALYZE

**Comprobación previa obligatoria — ventas del día:**
Antes de medir, verificar que existen pedidos con `fecha = CURRENT_DATE` en
`foodstore_tp_u4`:

```sql
SELECT COUNT(*) FROM pedido
WHERE  fecha = CURRENT_DATE AND eliminado = FALSE;
```

Si el resultado es 0, el `REFRESH` producirá una vista vacía y las mediciones
no serán representativas. En ese caso, crear un caso de prueba controlado:
insertar al menos un pedido con `fecha = CURRENT_DATE` y sus detalles
correspondientes en `foodstore_tp_u4` antes de ejecutar las mediciones y el
`REFRESH`.

> **Validación manual requerida en DBeaver:**
> Ejecutar la comprobación previa. Si da 0, insertar datos de prueba con
> `fecha = CURRENT_DATE` antes de continuar.

**Mediciones a tomar y documentar:**

| # | Consulta | Qué observar |
|---|---|---|
| 1 | Consulta directa base (sección 2.1) **antes** de crear la vista | Plan completo, nodo de acceso a `detalle_pedido`, Rows Removed by Filter |
| 2 | `REFRESH MATERIALIZED VIEW mv_tp_u4_top5_cat_dia` | Confirmar que pobló filas; ejecutar EXCEPT A y B inmediatamente después |
| 3 | Lectura de la vista materializada (sección 2.6) con `EXPLAIN ANALYZE` | Tipo de nodo (debe ser `Seq Scan` sobre tabla pequeña); sin joins |
| 4 | Consulta directa base nuevamente con `EXPLAIN (ANALYZE, BUFFERS)` | Hit/miss de caché para descartar efecto de warm cache |

**Tabla de resultados** (a completar con los tiempos reales de esta unidad):

| Medición | Execution Time | Nodo principal |
|---|---|---|
| 1 — Consulta directa (antes del REFRESH) | — ms | — |
| 3 — Lectura de la vista materializada | — ms | — |
| Mejora aproximada | — | — |

Los tiempos de TP5 (`informe_mediciones_tp5.md`) corresponden a una base y una consulta
distintas; no deben reutilizarse como medición de este TP. La tabla se completa con los
valores reales de `foodstore_tp_u4`.

> **Validación manual requerida en DBeaver:**
> Ejecutar las cuatro mediciones con `EXPLAIN ANALYZE` real (no solo `EXPLAIN`).
> La auditoría EXCEPT (sección 2.7) debe ejecutarse inmediatamente después del
> REFRESH y antes de insertar nuevos datos.
> Si los datos de `foodstore_tp_u4` son escasos, documentar los tiempos observados
> sin forzar una conclusión.

---

## Parte 3 — Contenido y orden de los scripts y el informe

### 3.1 Script `sql/tp_fnbc_control_lote.sql`

Orden de bloques dentro del script:

1. **Comentario de encabezado** — base de ejecución (`foodstore_tp_u4`), propósito,
   advertencia de no ejecutar en `foodstore` ni `foodstore_tp5`.
2. **Creación de `control_lote_almacen`** — tabla original con los IDs literales
   de la consigna (lote_id, deposito_id, responsable_control_id) y PK
   `(lote_id, deposito_id)`.
3. **INSERT de las tres filas** `(501,30,801)`, `(502,30,801)`, `(503,31,802)`.
4. **Creación de `tp_u4_deposito`** — tabla maestra nueva, mínima.
5. **Creación de `tp_u4_lote`** — tabla maestra nueva, mínima.
6. **Creación de `tp_u4_r1_responsable_deposito`** (R1) — con PK `id_usuario`
   y FK a `tp_u4_deposito` y `usuario`.
7. **Creación de `tp_u4_r2_lote_responsable`** (R2) — con PK `(id_lote, id_usuario)`
   y FK a `tp_u4_lote` y `tp_u4_r1_responsable_deposito`.
8. **INSERTs en tablas maestras** — 2 depósitos y 3 lotes con nombres descriptivos,
   usando CTEs con `RETURNING` para capturar los IDs generados.
9. **Migración R1 y R2** — `INSERT … SELECT` desde `control_lote_almacen` resolviendo
   la correspondencia por nombre.
10. **Creación de la vista `tp_u4_v_control_lote_almacen`** — proyecta exactamente
    tres columnas: `lote_id`, `deposito_id`, `responsable_control_id`, con los
    valores de correspondencia con la consigna.
11. **Consulta de correspondencia visual** — muestra las tres filas de la vista junto
    a las tres filas de `control_lote_almacen`.
12. **Verificaciones de equivalencia** — EXCEPT dirección A (`control_lote_almacen`
    contra la vista) y dirección B (vista contra `control_lote_almacen`).
13. **Comentario de cierre** — instrucción de qué observar en DBeaver.

> No incluir `DROP TABLE` al inicio (el script es aditivo en `foodstore_tp_u4`).
> No incluir `CREATE DATABASE` ni conexión a otra base.

---

### 3.2 Script `sql/tp_desnormalizacion_top_categorias.sql`

Orden de bloques dentro del script:

1. **Comentario de encabezado** — base de ejecución (`foodstore_tp_u4`), propósito.
2. **Comprobación previa de ventas del día** — `SELECT COUNT(*)` de pedidos con
   `fecha = CURRENT_DATE`; comentario indicando qué hacer si es 0.
3. **Consulta directa base** — la consulta de sección 2.1, para medir con
   `EXPLAIN ANALYZE` antes de crear la vista.
4. **Creación de la vista materializada** `mv_tp_u4_top5_cat_dia` — `WITH DATA`.
5. **Creación del índice único** `uq_mv_tp_u4_top5_cat_dia` — sobre `(id_categoria)`.
6. **Consulta de lectura** sobre la vista con `LIMIT 5`, para medir con
   `EXPLAIN ANALYZE`.
7. **Verificación de equivalencia — Dirección A** (`control_lote_almacen` EXCEPT vista).
8. **Verificación de equivalencia — Dirección B** (vista EXCEPT `control_lote_almacen`).
9. **Bloque comentado de REFRESH CONCURRENTLY** — con instrucción de cuándo usarlo.
10. **Comentario de cierre** — instrucción de qué documentar en el informe.

---

### 3.3 Informe `docs/tp_u4/informe_tp_u4.md`

Secciones sugeridas y su contenido:

**1. Introducción**
- Base de trabajo: `foodstore_tp_u4`.
- Propósito de cada parte.

**2. Parte 1 — Análisis FNBC**
- Relación original `ControlLoteAlmacen(LoteID, DepositoID, ResponsableControlID)`
  con PK inicial `(LoteID, DepositoID)`.
- Dependencias funcionales DF1 y DF2 con justificación semántica.
- Clausuras de los cuatro subconjuntos relevantes y demostración de las dos claves
  candidatas: `{LoteID, DepositoID}` y `{LoteID, ResponsableControlID}`.
- Tabla de atributos: los **tres son primos**.
- Diagnóstico de violación FNBC por DF2 (`ResponsableControlID → DepositoID`);
  nota sobre la diferencia con 3FN (la relación sí está en 3FN).
- Descomposición en R1 (`ResponsableControlID, DepositoID`) y R2
  (`LoteID, ResponsableControlID`) con verificación de lossless join por el
  teorema de Heath y demostración sobre la instancia de la consigna.
- Tablas SQL creadas: `tp_u4_deposito`, `tp_u4_lote`,
  `tp_u4_r1_responsable_deposito`, `tp_u4_r2_lote_responsable`.
- Mapeo de conceptos originales a FoodStore (tabla de sección 1.7).
- Vista `tp_u4_v_control_lote_almacen` con sus tres columnas exactas.
- Resultados de las verificaciones EXCEPT (0 filas en cada dirección).

**3. Parte 2 — Desnormalización controlada**
- Comprobación previa de ventas del día y, si fue necesario, descripción del caso
  de prueba creado en `foodstore_tp_u4`.
- Consulta directa base y plan observado con `EXPLAIN ANALYZE` real.
- Justificación de la elección de vista materializada (incluyendo límite de
  desactualización entre refrescos).
- Definición de `mv_tp_u4_top5_cat_dia`, índice único y estrategia de REFRESH.
- Tabla de mediciones con `Execution Time` reales de este TP:

  | Medición | Execution Time | Nodo principal |
  |---|---|---|
  | Consulta directa (antes del REFRESH) | — ms | — |
  | Lectura de la vista materializada | — ms | — |
  | Mejora aproximada | — | — |

- Resultados de las verificaciones EXCEPT ejecutadas inmediatamente después del
  REFRESH (0 filas en cada dirección).
- Política de REFRESH (frecuencia y cuándo usar CONCURRENTLY).

**4. Herramientas de IA utilizadas (DUIA)**
- Herramienta, propósito, qué se aceptó, qué se corrigió o descartó.

**5. Conclusiones**
- Síntesis de lo implementado y verificado.
- Relación entre el análisis FNBC académico y el esquema FoodStore existente
  (que ya está en FNBC por diseño desde TP1).

---

### 3.4 Tabla consolidada de validaciones manuales requeridas

| # | Momento | Acción en DBeaver | Resultado esperado |
|---|---|---|---|
| 1 | Antes de ejecutar `tp_fnbc_control_lote.sql` | Confirmar que `id_usuario IN (1, 2)` existen y no están eliminados en `foodstore_tp_u4` | Filas presentes con `eliminado = FALSE` |
| 2 | Después de ejecutar el script hasta el paso 11 | Revisar la consulta de correspondencia visual (vista vs. tabla original) | 3 filas alineadas con la instancia de la consigna |
| 3 | Ídem | Ejecutar EXCEPT dirección A (`control_lote_almacen` EXCEPT vista) | 0 filas |
| 4 | Ídem | Ejecutar EXCEPT dirección B (vista EXCEPT `control_lote_almacen`) | 0 filas |
| 5 | Antes de `tp_desnormalizacion_top_categorias.sql` | Verificar ventas del día: `SELECT COUNT(*) FROM pedido WHERE fecha = CURRENT_DATE AND eliminado = FALSE` | Si es 0, insertar datos de prueba antes de continuar |
| 6 | Antes de crear la vista | Ejecutar `EXPLAIN ANALYZE` sobre la consulta directa base | Registrar `Execution Time` como línea base de este TP |
| 7 | Después del primer `REFRESH` | Confirmar que la vista tiene filas | Al menos 1 fila |
| 8 | Inmediatamente después del `REFRESH` y antes de insertar nuevos datos | Ejecutar EXCEPT dirección A (directa EXCEPT vista) | 0 filas |
| 9 | Ídem | Ejecutar EXCEPT dirección B (vista EXCEPT directa) | 0 filas |
| 10 | Con vista y datos disponibles | Ejecutar `EXPLAIN ANALYZE` sobre la lectura de la vista | Registrar `Execution Time` y completar la tabla del informe |

---

## Parte 4 — Plan de migración reversible

> Esta sección especifica cómo ejecutar la migración de `control_lote_almacen`
> a R1 y R2 de forma segura, con validación integrada y rollback explícito ante
> cualquier diferencia. La prueba se realiza en una **copia nueva de `foodstore_tp5`**,
> nunca en `foodstore`, `foodstore_tp2`, `foodstore_tp3`, `foodstore_tp4`,
> `foodstore_tp5` ni `foodstore_tp_u4`.
>
> Los nombres, tipos e IDs de esta sección son los exactos de
> `sql/tp_fnbc_control_lote.sql`. Si hay discrepancia, el SQL prevalece.

---

### 4.1 Base de trabajo para la migración

| Aspecto | Detalle |
|---|---|
| Base de prueba | Copia nueva de `foodstore_tp5`, denominada `foodstore_tp_u4_mig` o similar. |
| Nunca tocar | `foodstore`, `foodstore_tp2`, `foodstore_tp3`, `foodstore_tp4`, `foodstore_tp5`, `foodstore_tp_u4`. |
| Por qué una copia nueva | La migración incluye `CREATE TABLE`, `INSERT` y `CREATE VIEW`; si algo sale mal, basta con eliminar la base de prueba. |

> **Validación manual requerida en DBeaver:**
> Crear la copia antes de ejecutar cualquier bloque de esta sección:
> `CREATE DATABASE foodstore_tp_u4_mig TEMPLATE foodstore_tp5;`
> Conectarse a esa base y no volver a cambiar de conexión durante toda la sesión.

---

### 4.2 Precondiciones

Verificar manualmente en DBeaver **antes de abrir la transacción**. Si alguna falla,
no abrir el `BEGIN`.

| # | Precondición | Consulta de verificación | Resultado esperado |
|---|---|---|---|
| P1 | La base activa es la copia de prueba | `SELECT current_database();` | `foodstore_tp_u4_mig` (o el nombre elegido) |
| P2 | `id_usuario IN (1, 2)` existen y no están eliminados | `SELECT id_usuario, nombre_usuario, apellido, eliminado FROM usuario WHERE id_usuario IN (1,2) ORDER BY id_usuario;` | 2 filas con `eliminado = FALSE` |
| P3 | No existe `control_lote_almacen` | `SELECT to_regclass('public.control_lote_almacen');` | `NULL` |
| P4 | No existe `tp_u4_deposito` | `SELECT to_regclass('public.tp_u4_deposito');` | `NULL` |
| P5 | No existe `tp_u4_lote` | `SELECT to_regclass('public.tp_u4_lote');` | `NULL` |
| P6 | No existe `tp_u4_responsable_control` | `SELECT to_regclass('public.tp_u4_responsable_control');` | `NULL` |
| P7 | No existe `tp_u4_responsable_usuario` | `SELECT to_regclass('public.tp_u4_responsable_usuario');` | `NULL` |
| P8 | No existe `tp_u4_r1_responsable_deposito` | `SELECT to_regclass('public.tp_u4_r1_responsable_deposito');` | `NULL` |
| P9 | No existe `tp_u4_r2_lote_responsable` | `SELECT to_regclass('public.tp_u4_r2_lote_responsable');` | `NULL` |
| P10 | No existe la vista | `SELECT to_regclass('public.tp_u4_v_control_lote_almacen');` | `NULL` |

---

### 4.3 Estructura de la transacción

Todo el DDL y DML de la migración se ejecuta dentro de un único bloque
`BEGIN … COMMIT`. Ningún paso se confirma por separado.

```
BEGIN;

  -- Bloque A: tablas maestras con IDs literales (SIN IDENTITY)
  -- Bloque B: poblado de maestras y tabla de correspondencia con usuario
  -- Bloque C: relación original con FKs hacia las maestras
  -- Bloque D: R1 y R2 (descomposición FNBC)
  -- Bloque E: migración de datos con INSERT … SELECT directo
  -- Bloque F: vista de compatibilidad
  -- Bloque G: validación EXCEPT (DO $$ … $$; si falla, la transacción queda
  --           abortada y el operador ejecuta ROLLBACK en la misma conexión)

COMMIT;   -- solo si el Bloque G no levantó excepción
```

**Comportamiento de errores:**
PostgreSQL marca la transacción como abortada ante cualquier error de sentencia,
pero no ejecuta `ROLLBACK` por sí solo: el operador debe ejecutarlo manualmente
en la misma conexión de DBeaver. Hasta ese momento, ninguna nueva sentencia válida
puede ejecutarse ("ERROR: current transaction is aborted"). Una vez ejecutado
`ROLLBACK`, la base queda exactamente como estaba antes del `BEGIN`.

---

### 4.4 Bloque A — Tablas maestras con IDs literales

Las tres tablas maestras usan `BIGINT PRIMARY KEY` **sin** `GENERATED ALWAYS AS IDENTITY`.
Los IDs de la consigna (30, 31, 501, 502, 503, 801, 802) se insertan como valores
literales y se conservan en todo el ejercicio.

```
tp_u4_deposito(
    id_deposito BIGINT PRIMARY KEY,    -- 30, 31
    nombre      VARCHAR(80) NOT NULL UNIQUE
)

tp_u4_lote(
    id_lote  BIGINT PRIMARY KEY,       -- 501, 502, 503
    nombre   VARCHAR(80) NOT NULL UNIQUE
)

tp_u4_responsable_control(
    id_responsable BIGINT PRIMARY KEY, -- 801, 802
    nombre         VARCHAR(80) NOT NULL UNIQUE
)
```

---

### 4.5 Bloque B — Poblado de maestras y tabla de correspondencia con `usuario`

Dentro del mismo `BEGIN`:

1. INSERT en `tp_u4_deposito`: `(30, 'Deposito A')`, `(31, 'Deposito B')`.
2. INSERT en `tp_u4_lote`: `(501,'Lote 501')`, `(502,'Lote 502')`, `(503,'Lote 503')`.
3. INSERT en `tp_u4_responsable_control`: `(801,'Responsable 1')`, `(802,'Responsable 2')`.
4. Creación de `tp_u4_responsable_usuario` — tabla separada con FK a
   `tp_u4_responsable_control` y FK a `usuario`. Vincula los IDs literales de la
   consigna con `usuario.id_usuario` del seed, **sin** reemplazar los IDs en R1/R2.
5. INSERT en `tp_u4_responsable_usuario`: `(801, 1)`, `(802, 2)`.

```
tp_u4_responsable_usuario(
    id_responsable BIGINT NOT NULL PRIMARY KEY
                   REFERENCES tp_u4_responsable_control(id_responsable),
    id_usuario     BIGINT NOT NULL UNIQUE
                   REFERENCES usuario(id_usuario)
)
```

**Por qué una tabla separada:** R1 y R2 operan con los IDs literales 801/802 de la
consigna. La correspondencia con `usuario.id_usuario` es un metadato del ejercicio
que no forma parte de la descomposición FNBC; mantenerla separada evita alterar la
semántica de R1/R2.

---

### 4.6 Bloque C — Relación original con FKs

Dentro del mismo `BEGIN`, se crea `control_lote_almacen` con FKs hacia las tres
tablas maestras. Es la **fuente de reversión**; permanece en la base después del
`COMMIT` y nunca se elimina en la migración normal.

```
control_lote_almacen(
    lote_id                BIGINT NOT NULL REFERENCES tp_u4_lote(id_lote),
    deposito_id            BIGINT NOT NULL REFERENCES tp_u4_deposito(id_deposito),
    responsable_control_id BIGINT NOT NULL REFERENCES tp_u4_responsable_control(id_responsable),
    PRIMARY KEY (lote_id, deposito_id)
)
```

Filas a insertar:

| lote_id | deposito_id | responsable_control_id |
|---|---|---|
| 501 | 30 | 801 |
| 502 | 30 | 801 |
| 503 | 31 | 802 |

---

### 4.7 Bloque D — R1 y R2 (descomposición FNBC)

Dentro del mismo `BEGIN`:

```
tp_u4_r1_responsable_deposito(
    responsable_control_id BIGINT NOT NULL PRIMARY KEY
                           REFERENCES tp_u4_responsable_control(id_responsable),
    deposito_id            BIGINT NOT NULL
                           REFERENCES tp_u4_deposito(id_deposito)
)

tp_u4_r2_lote_responsable(
    lote_id                BIGINT NOT NULL REFERENCES tp_u4_lote(id_lote),
    responsable_control_id BIGINT NOT NULL
                           REFERENCES tp_u4_r1_responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
)
```

La FK de R2 referencia la PK de R1 (`responsable_control_id`), garantizando que no
puede existir una asignación de lote a un responsable sin depósito registrado en R1.

---

### 4.8 Bloque E — Migración con INSERT … SELECT directo

Porque las tablas maestras conservan los IDs literales de la consigna, la migración
no necesita CTEs ni JOINs por nombre.

Dentro del mismo `BEGIN`:

1. INSERT en R1: `SELECT DISTINCT responsable_control_id, deposito_id FROM control_lote_almacen`.
   Resultado esperado: 2 filas.
2. INSERT en R2: `SELECT lote_id, responsable_control_id FROM control_lote_almacen`.
   Resultado esperado: 3 filas.

**Ningún paso modifica `control_lote_almacen`.**

---

### 4.9 Bloque F — Vista de compatibilidad

Dentro del mismo `BEGIN`:

```
tp_u4_v_control_lote_almacen AS
SELECT
    r2.lote_id                AS lote_id,
    r1.deposito_id            AS deposito_id,
    r2.responsable_control_id AS responsable_control_id
FROM   tp_u4_r2_lote_responsable r2
JOIN   tp_u4_r1_responsable_deposito r1
    ON r1.responsable_control_id = r2.responsable_control_id
```

La vista proyecta `r2.lote_id`, `r1.deposito_id` y `r2.responsable_control_id`.
No expone `id_usuario` ni ninguna columna del esquema FoodStore.

---

### 4.10 Bloque G — Validación EXCEPT

Dentro del mismo `BEGIN`, **inmediatamente después de crear la vista**:

```
DO $$
DECLARE
    v_diff_a INTEGER;
    v_diff_b INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_diff_a
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   tp_u4_v_control_lote_almacen
    ) t;

    SELECT COUNT(*) INTO v_diff_b
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   tp_u4_v_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   control_lote_almacen
    ) t;

    IF v_diff_a > 0 OR v_diff_b > 0 THEN
        RAISE EXCEPTION
            'Validación EXCEPT fallida: dirección A = %, dirección B = %',
            v_diff_a, v_diff_b;
    END IF;
END;
$$;
```

**Si `RAISE EXCEPTION` se ejecuta:** la transacción queda abortada. El operador
debe ejecutar `ROLLBACK` en la misma conexión de DBeaver. Ninguna tabla ni dato
nuevo queda persistido.

**Si el bloque termina sin excepción:** `v_diff_a = 0` y `v_diff_b = 0`; la
migración es equivalente a la relación original y la transacción puede confirmarse.

---

### 4.11 Revisión antes del COMMIT

Antes de ejecutar `COMMIT`, verificar visualmente (dentro de la transacción abierta):

| # | Consulta de revisión | Resultado esperado |
|---|---|---|
| R1 | `SELECT * FROM control_lote_almacen ORDER BY lote_id;` | 3 filas: (501,30,801), (502,30,801), (503,31,802) |
| R2 | `SELECT * FROM tp_u4_v_control_lote_almacen ORDER BY lote_id;` | 3 filas idénticas a R1 |
| R3 | `SELECT * FROM tp_u4_r1_responsable_deposito ORDER BY responsable_control_id;` | 2 filas: (801,30), (802,31) |
| R4 | `SELECT * FROM tp_u4_r2_lote_responsable ORDER BY lote_id;` | 3 filas: (501,801), (502,801), (503,802) |
| R5 | `SELECT id_responsable, id_usuario FROM tp_u4_responsable_usuario ORDER BY id_responsable;` | 2 filas: (801,1), (802,2) |

Solo ejecutar `COMMIT` si todas las consultas coinciden. Si alguna no coincide,
ejecutar `ROLLBACK` y revisar el bloque correspondiente.

---

### 4.12 ROLLBACK ante cualquier error

**Cuándo ejecutar ROLLBACK:**
- Cualquier sentencia dentro del `BEGIN` produce un error (la transacción queda
  abortada; el operador ejecuta `ROLLBACK` en la misma conexión de DBeaver).
- El Bloque G levanta la excepción EXCEPT.
- Cualquier consulta de revisión (sección 4.11) no coincide con el resultado esperado.
- El operador tiene cualquier duda antes de confirmar.

**Efecto:**
- Ninguna tabla ni vista de la migración queda creada.
- La base de prueba queda exactamente en el estado anterior al `BEGIN`.
- En PostgreSQL, el DDL es transaccional: `ROLLBACK` deshace `CREATE TABLE` y
  `CREATE VIEW` ejecutados dentro del mismo `BEGIN`.

---

### 4.13 Reversión post-COMMIT — qué conservar y qué retirar

Después de un `COMMIT` exitoso, `control_lote_almacen` **y sus tablas maestras**
(`tp_u4_deposito`, `tp_u4_lote`, `tp_u4_responsable_control`,
`tp_u4_responsable_usuario`) permanecen en la base como fuente de reversión.

`control_lote_almacen` tiene FK hacia las tres maestras de ID literales. Si se
intentara eliminar alguna maestra, PostgreSQL rechazaría la operación por FK activa.
Por eso la reversión solo retira la vista, R2 y R1, respetando las dependencias
**sin usar CASCADE**:

```
BEGIN;
  DROP VIEW  tp_u4_v_control_lote_almacen;
  DROP TABLE tp_u4_r2_lote_responsable;         -- referencia FK → R1
  DROP TABLE tp_u4_r1_responsable_deposito;     -- referencia FK → maestras
  -- Las tablas maestras, tp_u4_responsable_usuario y control_lote_almacen
  -- NO se eliminan: son la fuente de reversión con los datos originales.
COMMIT;
```

Cada `DROP TABLE` debe ejecutarse en el orden indicado; invertirlo produce un error
de FK y aborta la transacción. Tras esta reversión parcial, `control_lote_almacen`
sigue disponible con las tres filas originales y puede usarse para repetir la
migración desde cero.

---

### 4.14 Qué registrar en el informe

| # | Qué registrar | Qué debe mostrar |
|---|---|---|
| E1 | `SELECT current_database()` antes del `BEGIN` | Nombre de la base de prueba (no `foodstore_tp5` ni `foodstore_tp_u4`) |
| E2 | Resultado de P1–P10 (precondiciones) | Todos los valores esperados de la sección 4.2 |
| E3 | Salida del Bloque G (`DO $$ … $$`) | Ausencia de mensaje de error; `DO` finalizado sin excepción |
| E4 | Resultado de R1–R5 (revisión pre-COMMIT) | Filas exactas de la sección 4.11 |
| E5 | `SELECT * FROM tp_u4_v_control_lote_almacen ORDER BY lote_id` post-COMMIT | 3 filas: (501,30,801), (502,30,801), (503,31,802) |
| E6 | EXCEPT dirección A post-COMMIT | 0 filas |
| E7 | EXCEPT dirección B post-COMMIT | 0 filas |

**Lo que el informe no debe afirmar:**
- No indicar que la migración "ya fue ejecutada" en ninguna base productiva.
- No reutilizar tiempos ni resultados de TPs anteriores.
- Si la prueba aún no se realizó, dejar E3–E7 como "pendiente de ejecución" y
  completarlos con los valores reales después de ejecutar.
