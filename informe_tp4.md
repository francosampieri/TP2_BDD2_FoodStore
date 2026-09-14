# Informe TP4 — FoodStore

Base de trabajo: `foodstore_tp3` (PostgreSQL 17). Todas las mediciones corresponden a `EXPLAIN ANALYZE` tomando el `Execution Time` como tiempo real.

---

## Parte 1 — Reescrituras analíticas probadas (comparación contra el plan original)

### 1.1 Facturación por categoría y mes

| Aspecto | Consulta original (946,611 ms) | Reescritura probada (1089,669 ms) |
|---|---|---|
| Joins | `Parallel Hash Join` detalle_pedido–pedido; `Hash Join` con producto; `Hash Join` con categoria | Mismos joins (no cambia la combinación) |
| Agregación | `GroupAggregate` en dos fases (Partial + Finalize), paralelo | `Partial HashAggregate` en memoria |
| Nodo dominante | `Sort` `external merge` (4,5–4,8 MB de disco por proceso) antes del `Partial GroupAggregate`, por agrupar el texto ancho `nombre_categoria` | `HashAggregate` sin sort previo (elimina el ordenamiento) |
| Estrategia | `GROUP BY nombre_categoria, date_trunc('month', fecha)` | Agrupar por `id_categoria` y unir `categoria` al final solo para el rótulo |
| Decisión | — | **Descartada** |

**Lectura:** la reescritura alcanzó el objetivo estructural (evitar el sort de texto ancho: el planner eligió `HashAggregate`), pero el tiempo real empeoró (1089,669 ms vs. 946,611 ms). No se sustituye la consulta original.

### 1.2 Ranking de usuarios por gasto (subtotales)

| Aspecto | Consulta original (1283,410 ms) | Reescritura probada (2599,644 ms) |
|---|---|---|
| Joins | `Hash Join` detalle_pedido–pedido; `Hash Join` pedido–usuario | Mismos joins |
| Nodo dominante | `Sort` `external merge` de ~400.000 filas (29.416 kB de disco) antes del `GroupAggregate`, provocado por el `COUNT(DISTINCT ped.id_pedido)` sobre el join que replica cada pedido por detalle | `HashAggregate` por pedido (41 batches, 15.832 kB de disco) + `HashAggregate` por usuario (5 batches, 11.080 kB de disco) |
| Estrategia | `COUNT(DISTINCT ped.id_pedido)` + agregación directa | Pre-agregar `detalle_pedido` por `id_pedido` y luego agrupar por usuario (elimina el `COUNT(DISTINCT)`) |
| Decisión | — | **Descartada** |

**Lectura:** la reescritura eliminó el `COUNT(DISTINCT)` y su sort de 400.000 filas, pero los `HashAggregate` volcaron a disco en batches (memoria insuficiente) y el tiempo real empeoró (2599,644 ms vs. 1283,410 ms). No se sustituye la consulta original.

**Conclusión Parte 1:** ninguna reescritura superó a su original en tiempo real; ambas fueron descartadas y se mantienen las consultas originales.

---

## Parte 2 — Lectura crítica del plan (facturación, 946,611 ms)

Texto del plan leído: `Incremental Sort` → `Finalize GroupAggregate` → `Gather Merge` → `Partial GroupAggregate` → `Sort (external merge)` → `Hash Join` (producto–categoria) → `Hash Join` (detalle–producto) → `Parallel Hash Join` (detalle–pedido).

OpenCode generó 9 afirmaciones nodo a nodo. Después de la revisión:

| Afirmación | Contenido (resumen) | Resultado |
|---|---|---|
| 1 | `Incremental Sort` raíz: implementa `ORDER BY mes, facturado DESC`; entrada presorted por mes; 3 grupos re-ordenados, quicksort en memoria (26 kB); 91 filas reales vs. 40.150 estimadas | **Aceptada** |
| 2 | `Finalize GroupAggregate`: consolida las agregaciones parciales agrupando por mes + `nombre_categoria`; 91 grupos | **Aceptada** |
| 3 | `Gather Merge`: fusiona los parciales de los 2 workers; 273 filas = 91 × 3 procesos (líder + 2 workers) | **Aceptada** |
| 4 | `Partial GroupAggregate`: agrega parcialmente en cada proceso, 91 filas por loop | **Aceptada** |
| 5 | `Sort` `external merge`: 133.345 filas/loop por clave (mes, categoría); vuelca a disco (4584 kB líder; 4744/4808 kB workers) por exceder `work_mem` | **Aceptada** |
| 6 | `Hash Join` producto–categoria: lado build = `categoria` (8 filas reales, 9 kB); lado probe = resultado previo | **Aceptada** |
| 7 | `Hash Join` detalle–producto: lado build = `producto` (50.025 filas, 2857 kB); lado probe = resultado previo | **Aceptada** |
| 8 | `Parallel Hash Join` detalle–pedido: la última oración afirmaba que existía un `Hash` simple sobre `pedido` como build del join paralelo | **Rechazada** (solo la última oración) |
| 9 | Loops/workers y estimación vs. real: el tiempo de cada nodo es por loop (`rows × loops`); `categoria` estimada en 110 filas vs. 8 reales; Planning 41,239 ms aparte del Execution Time 946,611 ms | **Aceptada** |

### Corrección de la afirmación 8

En el `Parallel Hash Join` sobre `dp.id_pedido = ped.id_pedido`, **no existe un `Hash` simple sobre `pedido`**. `pedido` se lee con `Parallel Seq Scan` y con esa lectura se construye un **`Parallel Hash`** (262.144 buckets, 11.488 kB), que es el lado build del join paralelo. En el plan, los **`Hash` simples** corresponden solo a `producto` (2857 kB) y a `categoria` (9 kB), lados build de los dos Hash Joins seriales posteriores. El lado probe del `Parallel Hash Join` es `detalle_pedido` (también por `Parallel Seq Scan`).

### Correcciones de forma

- Typo corregido: **`factuado` → `facturado`** en todas las menciones de la columna de facturación.

---

## Parte 3 — Equivalencias y verificaciones (Spec A y Spec B)

- `spec_consultas_tp4.md` fue creado por Kiro.
- `sql/consultas_parte3_tp4.sql` fue generado por OpenCode.

### Spec A — Ranking de productos por facturación dentro de su categoría (RANK)

- Consulta 1: `RANK() OVER (PARTITION BY categoria.id_categoria ORDER BY SUM(detalle_pedido.subtotal) DESC)`, con filtros `eliminado = FALSE` en `categoria`, `producto` y `detalle_pedido`.
- Alternativa 1: la agregación se materializa en un CTE y el `RANK` se calcula después sobre la columna `facturacion` ya agregada.

**Equivalencia:** mismo `GROUP BY` (id/nombre de categoría y de producto), mismas métricas (`SUM(cantidad)`, `SUM(subtotal)`), mismos tres filtros de `eliminado` y mismo `RANK` por facturación dentro de cada categoría (empates comparten puesto). Difieren solo en la ubicación de la agregación: `RANK` sobre `SUM(dp.subtotal)` y `RANK` sobre la columna agregada `f.facturacion` producen valores idénticos por grupo.

### Spec B — Pedidos cuyo total supera el promedio personal (subconsulta correlacionada)

- Consulta 2: subconsulta correlacionada por `id_usuario` (`AVG(p2.total)` sobre pedidos no eliminados del mismo usuario), comparación estrictamente mayor (`>`), sobre `usuario`+`pedido` filtrados por `eliminado = FALSE`.
- Alternativa 2: CTE `promedio_usuario` que calcula `AVG(total)` por usuario (mismos filtros) y `JOIN` por `id_usuario`.

**Equivalencia:** el CTE calcula exactamente el mismo promedio con los mismos filtros. Todo usuario que aparece en la consulta principal tiene al menos un pedido no eliminado, por lo que el `INNER JOIN` contra el CTE no descarta ninguna fila que el original devuelva. La comparación sigue siendo estricta (`>`) contra el mismo promedio, con el mismo `ORDER BY total DESC, id_pedido ASC`.

### Resultado de las verificaciones

Las cuatro verificaciones `EXCEPT` (comparando todas las columnas de salida, en ambos sentidos) fueron ejecutadas manualmente sobre `foodstore_tp3`:

| Verificación | Dirección | Filas devueltas |
|---|---|---|
| A.1 | Consulta 1 `EXCEPT` Alternativa 1 | 0 |
| A.2 | Alternativa 1 `EXCEPT` Consulta 1 | 0 |
| B.1 | Consulta 2 `EXCEPT` Alternativa 2 | 0 |
| B.2 | Alternativa 2 `EXCEPT` Consulta 2 | 0 |

0 filas en las cuatro direcciones: consultas y alternativas son semánticamente equivalentes fila a fila.

---

## Parte 4 — Competencia: consulta común de la cátedra

La consulta común de la cátedra, adaptada al esquema FoodStore (disponible en `sql/competencia_tp4.sql`):

> Por indicación explícita del profesor, esta competencia reutiliza la consulta común del TP3. Esta instrucción específica prevalece sobre el ejemplo general de consulta analítica con JOIN y agregación indicado en la guía.

```sql
SELECT id_producto AS id,
       nombre_producto AS nombre,
       precio,
       stock
FROM producto
WHERE id_categoria = 1
  AND disponible = TRUE
  AND eliminado = FALSE
  AND precio BETWEEN 1000 AND 3000
ORDER BY precio DESC;
```

### Índice reutilizado

Se reutiliza el índice **`idx_producto_cat_precio_disp_vig`**, creado y aceptado en el TP3 (Parte 5) sobre `producto (id_categoria, precio DESC) WHERE disponible = TRUE AND eliminado = FALSE`. No se incluye ningún `CREATE INDEX` ni DDL en el script de TP4 porque el índice ya existe en `foodstore_tp3`.

### Resultados reales (medición realizada en TP3 sobre `foodstore_tp3`; no se volvió a ejecutar)

| Aspecto | Antes | Después |
|---|---|---|
| Índice usado | `idx_producto_id_categoria` (Bitmap Heap Scan) | `idx_producto_cat_precio_disp_vig` (Bitmap Index Scan) |
| Filas recuperadas | 7.147 | 3.167 |
| Filas descartadas | ~3.980 (Rows Removed by Filter) | 0 (sin Rows Removed by Filter) |
| Execution Time | 93,394 ms | 10,855 ms |

**Mejora aproximada: 8.6x** (93,394 ms → 10,855 ms).

**Aclaración sobre el Sort:** el nodo `Sort` (por `precio DESC`) permaneció en ambos planes. La mejora del tiempo real no proviene de eliminar el ordenamiento final, sino del **acceso filtrado por el índice**: `idx_producto_cat_precio_disp_vig` aplica de antemano la categoría, el rango de precio, `disponible` y `eliminado`, de modo que al heap entran solo las 3.167 filas del resultado, sin `Rows Removed by Filter`; antes, con `idx_producto_id_categoria`, el plan traía 7.147 filas de la categoría y descartaba ~3.980 con el resto de los filtros. La evidencia corresponde a la medición real realizada en el TP3 sobre `foodstore_tp3` (post `ANALYZE`, documentada en `sql/competencia_optimizacion_tp3.sql`).