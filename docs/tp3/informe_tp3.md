# Informe TP3 — FoodStore

**Base de trabajo:** `foodstore_tp3` (PostgreSQL 17). Nunca se modificaron `foodstore` ni `foodstore_tp2`.

---

## Parte 1 — Carga masiva

Script: `sql/carga_masiva_tp3.sql`.

Resultados de la carga validada:

| Objeto | Cantidad cargada |
|---|---|
| Productos (`TP3_Producto_*`) | 50.000 |
| Usuarios (`tp3_usuario_*@mail.com`) | 20.000 |
| Pedidos | 200.000 |
| Detalles de pedido | 400.000 (exactamente 2 por pedido) |

Verificaciones:

- **V1** (conteos): 50.000 / 20.000 / 200.000 — correctos.
- **V2** (detalles por pedido = 2): **0 filas**.
- **V3** (total = SUM subtotal por pedido): **0 filas**.
- **V4** (subtotal = cantidad × precio_unitario): **0 filas**.
- **V5** (mails duplicados): **0 filas**.
- **V6** (pedidos sin detalles): **0 filas**.
- **V7** (cantidad ≤ 0 en detalles): **0 filas**.

---

## Parte 2 — Índices y optimización

Script: `sql/indices_optimizacion_tp3.sql`.

Tabla comparativa de Execution Time real (medido con `EXPLAIN ANALYZE` post `ANALYZE`):

| Consulta | Nodo principal antes | Costo est. antes | Execution Time antes | Nodo principal después | Costo est. después | Execution Time después | Índice probado | Decisión |
|---|---|---|---|---|---|---|---|---|
| Q1 | Sort | 1058.39..1060.37 | 7.744 ms | Sort | 912.26..914.26 | 57.370 ms | `idx_producto_cat_precio_vig` | **Descartado** |
| Q2 | Sort | 4971.66..4985.37 | 182.260 ms | Sort | 4659.63..4673.70 | 288.887 ms | `idx_pedido_fecha_conf_vig` | **Descartado** |
| Q3 | Gather Merge | 7242.32..7243.02 | 406.794 ms | Sort | 84.62..84.64 | 16.355 ms | `idx_detalle_pedido_producto_vig` | **Aceptado** |

Observaciones por consulta:

- **Q1**: rechazado. El plan continuó con `Bitmap Heap Scan` + `Sort` y el Execution Time aumentó (7.744 → 57.370 ms).
- **Q2**: rechazado. El plan continuó con `Bitmap Heap Scan` + `Sort` y el Execution Time aumentó (182.260 → 288.887 ms).
- **Q3**: aceptado. El acceso pasó de `Parallel Seq Scan` a `Index Scan` sobre `idx_detalle_pedido_producto_vig` (mejora aproximada **~25x**, 406.794 → 16.355 ms); el nodo raíz pasó a ser el `Sort`.

Solo se mantiene en el repositorio el índice aceptado (`idx_detalle_pedido_producto_vig`); los índices de Q1 y Q2 se descartaron por evidencia real de Execution Time y no se conservan.

---

## Parte 3 — Lectura crítica de plan real

Plan analizado: Q3 optimizado (nodo a nodo, solo a partir del texto del plan).

Tabla de afirmaciones de la lectura crítica:

| # | Afirmación | Estado |
|---|---|---|
| 1 | El nodo raíz es un `Sort` por `fecha DESC` con quicksort en 25 kB; costo estimado 84.62..84.64, 8 filas estimadas y 8 reales en 11.804..11.806 ms. | Aceptada |
| 2 | La estimación de filas (8) coincidió con lo real en `Sort`, `Nested Loop` y acceso a `detalle_pedido`. | Aceptada |
| 3 | El InitPlan 1 es una búsqueda puntual de `TP3_Producto_1` por `idx_producto_nombre`, 1 fila estimada y 1 real, ejecutada una sola vez (loops=1). | Aceptada |
| 4 | El `Nested Loop` une los 8 detalles con sus pedidos: costo 0.84..76.06, 8 filas en 4.760..9.463 ms. | Aceptada |
| 5 | El lado impulsor es un `Index Scan` sobre `idx_detalle_pedido_producto_vig` que encontró los 8 detalles por `id_producto` sin barrer la tabla. | Aceptada |
| 6 | El lado derecho es un `Index Scan on pedido_pkey` con 1 fila por ejecución, ejecutado 8 veces (loops=8), ~0.642 ms por look-up. | Aceptada |
| 7 | `Planning Time` (36.590 ms) y `Execution Time` (16.355 ms) son categorías distintas; el costo estimado (84.62) no es tiempo. | Aceptada |
| 8 | "No se puede saber si el plan ejecutó en paralelo" — afirmación **rechazada**: la ausencia de nodos `Gather`, paralelización y `Workers` demuestra que el plan fue **serial**. | **Rechazada** |

La única afirmación rechazada de la lectura fue la número 8: sí puede concluirse el carácter serial del plan por la ausencia de nodos `Gather`/`Parallel` y de `Workers Launched/Planned`.

---

## Parte 4 — Consultas y equivalencia

Script: `sql/consultas_parte4_tp3.sql`.

- **Consulta A** (resumen/agregación sobre `usuario` y `pedido`) y **Alternativa A** (agregación previa en CTE + `LEFT JOIN` contra `usuario`).
- **Consulta B** (subconsulta correlacionada sobre `producto` y `categoria`) y **Alternativa B** (`AVG` por categoría en CTE + `JOIN`).

Resultado de la equivalencia formal con `EXCEPT` (cuatro verificaciones comparando todas las columnas):

| Verificación | Filas en cada dirección |
|---|---|
| Consulta A − Alternativa A | 0 |
| Alternativa A − Consulta A | 0 |
| Consulta B − Alternativa B | 0 |
| Alternativa B − Consulta B | 0 |

Las cuatro verificaciones de equivalencia reales devolvieron **0 filas en cada dirección**: los pares son equivalentes en conjunto (mismas columnas, mismos filtros y mismos resultados con el mismo `LIMIT`).

---

## Parte 5 — Competencia de optimización

Script: `sql/competencia_optimizacion_tp3.sql`.

**Consulta común de la cátedra adaptada al esquema FoodStore:**

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

**Estrategia:** la consulta filtra por `id_categoria`, vigencia y rango de precio ordenando por `precio DESC`. Sin índice específico el planner usaba `idx_producto_id_categoria` (Bitmap Heap Scan) trayendo ~7.147 filas de la categoría y descartando ~3.980 por los filtros restantes. El índice probado combina categoría con precio y aplica de antemano los filtros de vigencia.

**Comparación antes / después:**

| Métrica | Antes | Después |
|---|---|---|
| Nodo raíz (Sort) | costo 1225.98..1234.01 | costo 1140.54..1148.41 |
| Acceso a producto | `Bitmap Heap Scan` con `idx_producto_id_categoria` | `Bitmap Index Scan` con `idx_producto_cat_precio_disp_vig` |
| Filas traídas al heap | 7.147 (3.980 descartadas por filtros) | 3.167, sin "Rows Removed by Filter" |
| Heap Blocks | exact=810 | exact=738 |
| Execution Time | 93.394 ms | 10.855 ms |

**Índice aceptado:**

```sql
CREATE INDEX idx_producto_cat_precio_disp_vig
ON producto (id_categoria, precio DESC)
WHERE disponible = TRUE
  AND eliminado = FALSE;
```

**Resultado:** mejora aproximada de **8.6x** (93.394 ms → 10.855 ms). El `Sort` permaneció en ambos planes: el acceso por índice mejoró significativamente (menos filas al heap, sin `Rows Removed by Filter`), pero el orden final por `precio DESC` sigue requiriendo la ordenación. El índice se creó definitivamente y se ejecutó `ANALYZE producto`.

---

## Parte 6 — Pendientes

- Pendiente de la consulta común entregada por la cátedra (resuelta en la Parte 5).