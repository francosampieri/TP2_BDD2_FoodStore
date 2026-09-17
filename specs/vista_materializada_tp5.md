# Especificación de Vista Materializada — TP5 FoodStore Parte C

> Este documento especifica la vista materializada `mv_tp5_facturacion_categoria_mes`
> para la Parte C del TP5.
> No contiene `CREATE MATERIALIZED VIEW`, `CREATE INDEX` ni DDL de ningún tipo.
> Su propósito es ser entregado a OpenCode para guiar la implementación y medición posterior.

---

## Antecedente: por qué este reporte es candidato

La consulta de facturación por categoría y mes fue medida en TP4
(`consultas_analiticas_tp4.sql`, versión 1.1) con un `Execution Time`
de **946.611 ms** sobre `foodstore_tp3`. El plan involucra:

- `Parallel Hash Join` entre `detalle_pedido` y `pedido`.
- Dos `Hash Join` adicionales con `producto` y `categoria`.
- Un `Sort` con external merge de 4.5–4.8 MB de disco por proceso
  antes del `Partial GroupAggregate`.

Ambas reescrituras intentadas en TP4 empeoraron el tiempo real
(la variante con CTE llegó a 1089.669 ms). La consulta no tiene un
predicado selectivo de punto o rango que permita beneficiarse de un
índice B-tree: necesita leer y agregar **todas** las filas vigentes de
`detalle_pedido`. Esto la convierte en el caso ideal para una vista
materializada: el costo de los joins y la agregación se paga una sola
vez en el `REFRESH`; cada consulta posterior lee una tabla pequeña
y precomputada.

---

## Nombre

```
mv_tp5_facturacion_categoria_mes
```

---

## Lógica de origen

La vista materializa la siguiente agregación:

- Tabla base: `detalle_pedido`
- JOINs necesarios (para resolver categoría a partir del detalle):
  - `detalle_pedido → pedido` por `id_pedido`
  - `detalle_pedido → producto` por `id_producto`
  - `producto → categoria` por `id_categoria`
- Filtros de vigencia aplicados en la definición:
  - `detalle_pedido.eliminado = FALSE`
  - `pedido.eliminado = FALSE`
  - No se filtra `producto.eliminado` ni `categoria.eliminado`: la
    categoría y el producto son datos de clasificación histórica; un
    detalle cuyo producto o categoría fue eliminado posteriormente sigue
    siendo facturación real y debe contabilizarse.
- Agrupación: `categoria.id_categoria`, `categoria.nombre_categoria`,
  `date_trunc('month', pedido.fecha)`
- Agregado: `SUM(detalle_pedido.subtotal)`
- **Sin `ORDER BY` en la definición**: el orden se aplica al consultar
  la vista, no al materializarla. Incluirlo en la definición no tiene
  efecto en PostgreSQL y agrega confusión.

---

## Columnas exactas de la vista materializada

| Columna | Expresión de origen | Tipo resultante | Descripción |
|---|---|---|---|
| `id_categoria` | `categoria.id_categoria` | `BIGINT` | Identificador de la categoría (clave para el índice único) |
| `nombre_categoria` | `categoria.nombre_categoria` | `VARCHAR(80)` | Nombre de la categoría desnormalizado |
| `mes` | `date_trunc('month', pedido.fecha)` | `TIMESTAMPTZ` | Primer día del mes de facturación, truncado |
| `facturado` | `SUM(detalle_pedido.subtotal)` | `NUMERIC(12,2)` | Total facturado en esa categoría y mes |

La combinación `(id_categoria, mes)` identifica unívocamente cada fila
del resultado porque la agrupación garantiza exactamente una fila por
par categoría-mes.

---

## Consulta directa equivalente (base de medición)

Esta es la consulta que se medirá contra la vista materializada con
`EXPLAIN ANALYZE` para comparar tiempos:

```sql
SELECT c.id_categoria,
       c.nombre_categoria AS categoria,
       date_trunc('month', ped.fecha) AS mes,
       SUM(dp.subtotal) AS facturado
FROM   detalle_pedido dp
JOIN   pedido         ped ON ped.id_pedido  = dp.id_pedido
                          AND ped.eliminado  = FALSE
JOIN   producto       pr  ON pr.id_producto = dp.id_producto
JOIN   categoria      c   ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria,
          date_trunc('month', ped.fecha)
ORDER  BY mes, facturado DESC;
```

> Esta consulta es funcionalmente idéntica a la versión 1.1 de
> `consultas_analiticas_tp4.sql`, con el agregado de `c.id_categoria`
> en el `SELECT` y el `GROUP BY` para alinear la proyección con las
> columnas de la vista materializada. El tiempo base de referencia es
> **946.611 ms** (medición TP4 sobre `foodstore_tp3`).

---

## Consulta de lectura sobre la vista materializada

Una vez creada la vista y ejecutado el primer `REFRESH`, esta es la
consulta que se utilizará para lectura y medición:

```sql
SELECT id_categoria,
       nombre_categoria,
       mes,
       facturado
FROM   mv_tp5_facturacion_categoria_mes
ORDER  BY mes, facturado DESC;
```

Esta consulta debe producir exactamente el mismo resultado que la
consulta directa equivalente, en el mismo orden, y debe hacerlo con
un `Seq Scan` sobre la vista materializada (tabla precomputada pequeña)
en lugar de los cuatro joins y el sort de disco del plan original.

---

## Índice único posterior (para REFRESH CONCURRENTLY)

`REFRESH MATERIALIZED VIEW CONCURRENTLY` requiere que la vista tenga al
menos un índice único sobre columnas que identifiquen unívocamente cada
fila del resultado materializado.

**Columnas del índice único:** `(id_categoria, mes)`

**Justificación de la elección:**
- La agrupación garantiza exactamente una fila por par `(id_categoria, mes)`,
  por lo que esta combinación es la clave natural del resultado.
- Se usa `id_categoria` (entero) en lugar de `nombre_categoria` (texto)
  porque un índice sobre enteros es más compacto, más rápido de comparar
  y más estable ante posibles renombres de categoría.
- `mes` es de tipo `TIMESTAMPTZ` (resultado de `date_trunc`); el índice
  sobre él permite además consultas de rango temporal eficientes sobre
  la vista materializada.

Este índice se crea **después** de la primera ejecución de
`REFRESH MATERIALIZED VIEW mv_tp5_facturacion_categoria_mes` (que
pobla la vista). Intentar crear el índice único sobre una vista vacía
es válido, pero el `REFRESH CONCURRENTLY` posterior lo requiere ya
existente.

---

## Verificación de equivalencia entre consulta directa y vista materializada

Una vez creada la vista y ejecutado el primer `REFRESH`, la equivalencia
se verifica con `EXCEPT` en ambas direcciones. Si ambas consultas devuelven
cero filas, los resultados son idénticos.

**Dirección A — filas en la directa que no están en la vista:**
```sql
SELECT id_categoria,
       nombre_categoria AS categoria,
       mes,
       facturado
FROM (
    SELECT c.id_categoria,
           c.nombre_categoria,
           date_trunc('month', ped.fecha) AS mes,
           SUM(dp.subtotal) AS facturado
    FROM   detalle_pedido dp
    JOIN   pedido         ped ON ped.id_pedido  = dp.id_pedido
                              AND ped.eliminado  = FALSE
    JOIN   producto       pr  ON pr.id_producto = dp.id_producto
    JOIN   categoria      c   ON c.id_categoria = pr.id_categoria
    WHERE  dp.eliminado = FALSE
    GROUP  BY c.id_categoria, c.nombre_categoria,
              date_trunc('month', ped.fecha)
) directa

EXCEPT

SELECT id_categoria,
       nombre_categoria,
       mes,
       facturado
FROM   mv_tp5_facturacion_categoria_mes;
```

**Dirección B — filas en la vista que no están en la directa:**
```sql
SELECT id_categoria,
       nombre_categoria,
       mes,
       facturado
FROM   mv_tp5_facturacion_categoria_mes

EXCEPT

SELECT c.id_categoria,
       c.nombre_categoria,
       date_trunc('month', ped.fecha) AS mes,
       SUM(dp.subtotal) AS facturado
FROM   detalle_pedido dp
JOIN   pedido         ped ON ped.id_pedido  = dp.id_pedido
                          AND ped.eliminado  = FALSE
JOIN   producto       pr  ON pr.id_producto = dp.id_producto
JOIN   categoria      c   ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria,
          date_trunc('month', ped.fecha);
```

Ambas consultas deben devolver **cero filas**. Si alguna devuelve filas,
indica una discrepancia en los filtros o en la definición de la vista que
debe corregirse antes de continuar.

---

## Estrategia de actualización

### Naturaleza del dato materializado

La vista almacena facturación histórica agregada por mes. Los datos de
meses pasados son inmutables en condiciones normales: un pedido ya
terminado no cambia su `subtotal` ni su `fecha`. El único escenario que
altera datos históricos es la baja lógica tardía de un pedido o detalle
(`eliminado` pasa a `TRUE` después de que el pedido ya estaba terminado),
lo cual es infrecuente.

Los datos del mes en curso sí cambian con cada nuevo pedido confirmado.

### Frecuencia sugerida de REFRESH

| Escenario de uso | Frecuencia sugerida |
|---|---|
| Reporte mensual de cierre de período | Una vez al mes, al inicio del mes siguiente, después del cierre contable |
| Panel de control con datos del día actual | Una vez por día, en horario de baja actividad (madrugada) |
| Demo o entorno de desarrollo | Manual, antes de cada consulta de validación |

No se recomienda ejecutar `REFRESH` por cada INSERT en `detalle_pedido`:
el costo del refresh (que re-ejecuta los cuatro joins sobre toda la
tabla) supera el beneficio de mantener el dato en tiempo real. Para datos
en tiempo real, la consulta directa es más apropiada.

### Datos potencialmente desactualizados

Entre dos `REFRESH` consecutivos, la vista puede mostrar:
- Facturación del mes actual inferior a la real (no incluye pedidos
  creados después del último refresh).
- Filas de meses pasados desactualizadas si se realizaron bajas lógicas
  tardías de pedidos o detalles.

Este desfase es aceptable para reportes de cierre mensual y para análisis
histórico. No es aceptable para pantallas operativas en tiempo real
(como el total de un pedido activo), que deben consultar las tablas base
directamente.

### Cuándo usar REFRESH MATERIALIZED VIEW CONCURRENTLY

`REFRESH MATERIALIZED VIEW CONCURRENTLY` requiere el índice único sobre
`(id_categoria, mes)` (especificado arriba) y tiene las siguientes
ventajas respecto del `REFRESH` simple:

- **No bloquea lecturas**: mientras el refresh se ejecuta, la vista
  sigue respondiendo consultas con los datos anteriores. El refresh
  simple bloquea la tabla con `AccessExclusiveLock` durante toda la
  operación.
- **Adecuado para entornos con lecturas concurrentes**: si el panel de
  control consulta la vista mientras se ejecuta el refresh nocturno,
  `CONCURRENTLY` garantiza que esas consultas no sean bloqueadas.

Usar `REFRESH MATERIALIZED VIEW CONCURRENTLY` siempre que:
1. El índice único sobre `(id_categoria, mes)` exista.
2. Haya posibilidad de consultas simultáneas durante el refresh
   (entornos multi-usuario, paneles con polling).

Usar `REFRESH MATERIALIZED VIEW` (sin `CONCURRENTLY`) solo en:
- El primer refresh inicial (antes de crear el índice único, si se
  optó por ese orden).
- Entornos de desarrollo o demo donde no hay usuarios concurrentes
  y se prefiere simplicidad.

---

## Por qué la vista materializada es apropiada para este reporte

### Naturaleza de la consulta

La consulta de facturación por categoría y mes agrega **todas** las filas
vigentes de `detalle_pedido` sin predicado selectivo. Como se documentó en
`specs/plan_indexado_tp5.md` y se verificó en `informe_mediciones_tp5.md`,
este tipo de consulta no puede beneficiarse de índices B-tree: el planner
necesita leer la tabla completa independientemente del índice disponible.
El costo medido en TP4 (946.611 ms, con sort de disco de 4.5–4.8 MB)
refleja exactamente ese comportamiento.

### Qué aporta la materialización

Al precalcular y persistir el resultado, la vista materializada:
1. **Transforma el costo**: el join y la agregación se ejecutan una sola
   vez en el `REFRESH`, no en cada lectura del reporte.
2. **Reduce el tamaño de la tabla leída**: el resultado tiene una fila por
   par categoría-mes (pocas decenas de filas para un catálogo de 6
   categorías y datos de varios meses), frente a cientos de miles de
   filas en `detalle_pedido`.
3. **Elimina el sort de disco**: la tabla materializada cabe en memoria;
   el `ORDER BY` al consultarla opera sobre datos ya reducidos.

### Por qué no debe sustituir operaciones transaccionales

La vista materializada es una **instantánea del pasado en el momento del
último `REFRESH`**. No refleja el estado actual de la base de datos.
Por esta razón:

- **No debe usarse para calcular el total de un pedido activo**: esa
  lógica es responsabilidad del trigger `trg_total_ins`/`trg_total_upd`
  sobre la tabla `pedido`, que opera en tiempo real dentro de la
  transacción.
- **No debe usarse como fuente de verdad en decisiones de stock o
  facturación individual**: cualquier operación que dependa del estado
  actual de la base debe consultar las tablas base directamente.
- **No debe participar en transacciones de escritura**: la vista no
  es actualizable. `INSERT`, `UPDATE` y `DELETE` sobre ella no están
  soportados en PostgreSQL y deben dirigirse a las tablas base a través
  del procedimiento `sp_crear_pedido` y las operaciones CRUD estándar.

La vista materializada es exclusivamente una herramienta de lectura para
reportes analíticos de datos históricos agregados, complementaria al
modelo transaccional, no sustituta de él.
