# Informe de Mediciones — TP5 FoodStore

Base de trabajo: `foodstore_tp3` y `foodstore_tp5` (PostgreSQL 17). Medición manual en DBeaver. Los tiempos de lectura provienen de `EXPLAIN ANALYZE` (se toma el `Execution Time`).

---

# Parte A — Indexación

---

## Índices aceptados

| Índice | Tabla | Clave | Condición parcial |
|---|---|---|---|
| `idx_pedido_cancelado_fecha_vig` | `pedido` | `(fecha DESC)` | `WHERE eliminado = FALSE AND estado = 'CANCELADO'` |
| `idx_producto_no_disponible_nombre_vig` | `producto` | `(nombre_producto ASC)` | `WHERE eliminado = FALSE AND disponible = FALSE` |
| `idx_detalle_cantidad_excepcional_vig` | `detalle_pedido` | `(cantidad DESC, id_detalle ASC)` | `WHERE eliminado = FALSE AND cantidad >= 5` |

Definiciones completas, con consulta objetivo, plan previo y expectativas, en `sql/indices_tp5.sql`.

---

## Mediciones de lectura (antes / después)

### 1. Pedidos cancelados

| | Antes | Después |
|---|---|---|
| Nodo de acceso | `Parallel Seq Scan` sobre `pedido` | `Index Scan` usando `idx_pedido_cancelado_fecha_vig` |
| Execution Time | 210.677 ms | 2.822 ms |

**Mejora aproximada: 74.7x.**

### 2. Productos no disponibles

| | Antes | Después |
|---|---|---|
| Nodo de acceso | `Seq Scan` sobre `producto` | `Index Scan` usando `idx_producto_no_disponible_nombre_vig` |
| Execution Time | 31.581 ms | 2.767 ms |

**Mejora aproximada: 11.4x.** El `Sort` final (por `nombre_producto ASC`) permanece, pero opera sobre una sola fila, por lo que su costo es despreciable.

### 3. Detalles con cantidad >= 5

| | Antes | Después |
|---|---|---|
| Nodo de acceso | `Parallel Seq Scan` sobre `detalle_pedido` | `Index Scan` usando `idx_detalle_cantidad_excepcional_vig` |
| Execution Time | 182.874 ms | 1.498 ms |

**Mejora aproximada: 122x.**

---

## Medición de escritura

Mismo `INSERT` temporal de **300 detalles**, ejecutado dentro de `BEGIN`/`ROLLBACK` en cada base:

| Base | Estado de índices TP5 | Tiempo |
|---|---|---|
| `foodstore_tp3` | Sin índices TP5 | 989.437 ms |
| `foodstore_tp5` | Con índices TP5 | 325.245 ms |

> **Advertencia:** este resultado aislado **no demuestra** que los índices reduzcan el costo de escritura. La diferencia puede deberse a caché y a la variación normal de ejecución. Los triggers, las validaciones de FK y el recálculo de totales tuvieron un peso relevante en ambos casos y no permiten atribuir la mejora a los índices.

---

## Propuestas descartadas

1. **Índice simple sobre `pedido (eliminado)`** — baja cardinalidad: `eliminado` es booleano y casi todos los pedidos están vigentes, por lo que no aporta selectividad.
2. **Índices para agregaciones globales sin filtro selectivo** — las consultas que agregan todas las filas vigentes (p. ej., facturación por categoría/mes) necesitan recorrer las tablas completas; ningún índice B-tree evita esa lectura.
3. **Índice general sobre `pedido (total)` para "total mayor al promedio"** — devolvía 88.369 pedidos de 200.021, por lo que no era suficientemente selectivo y no justificaba su costo de mantenimiento.

---

# Parte B — Vistas de reporte

Tres vistas nuevas creadas en `sql/views_tp5.sql`, especificadas en `specs/tp5/vistas_tp5.md`. Las vistas existentes de `Objects.sql` no se modificaron ni reemplazaron.

## Vistas creadas y reglas principales

| Vista | Objetivo | Reglas principales |
|---|---|---|
| `v_tp5_productos_categoria` | Catálogo completo para reportes de inventario por categoría | Filtra `producto.eliminado = FALSE` y `categoria.eliminado = FALSE`; expone precio, stock, disponibilidad y categoría desnormalizada |
| `v_tp5_pedidos_usuario` | Reporte administrativo y auditoría con identidad completa del usuario | Filtra `pedido.eliminado = FALSE` y `usuario.eliminado = FALSE`; no expone `contrasena`, `celular` ni `rol` |
| `v_tp5_detalle_pedido_productos` | Historial de ventas con nombre del producto | Filtra solo `detalle_pedido.eliminado = FALSE`; conserva el nombre de productos históricos aunque `producto.eliminado = TRUE` |

## Verificación de equivalencia

Las verificaciones de `sql/test_vistas_tp5.sql` (V1.1–V3.2) se ejecutaron manualmente en DBeaver sobre `foodstore_tp5`: las **seis verificaciones EXCEPT dieron 0 filas**, confirmando que cada vista es idéntica a su consulta manual equivalente en todas las columnas expuestas.

## Regla de histórico (Vista 3)

La consulta de control V3.3 (`id_producto IN (4, 16)`) y la búsqueda general de detalles vigentes asociados a productos eliminados (`producto.eliminado = TRUE`) dieron **0 filas**. Por eso la regla histórica fue validada **por diseño y por equivalencia** (la vista no aplica el filtro de `producto.eliminado` y es idéntica a la consulta manual), pero **no pudo demostrarse visualmente** con registros existentes: la base no tiene casos de detalles vigentes ligados a productos eliminados.

---

# Parte C — Vista materializada

## Vista y estructura

- **Vista:** `mv_tp5_facturacion_categoria_mes` (definida en `sql/vista_materializada_tp5.sql`, spec en `specs/tp5/vista_materializada_tp5.md`).
- Resume la **facturación por categoría y mes** a partir de `detalle_pedido`, `pedido`, `producto` y `categoria` (agregación `SUM(subtotal)` agrupada por categoría y `date_trunc('month', fecha)`).
- Se crea con `WITH DATA` y tiene el índice único `uq_mv_tp5_facturacion_categoria_mes` sobre `(id_categoria, mes)`, requisito para futuros `REFRESH MATERIALIZED VIEW CONCURRENTLY`.

## Mediciones

La consulta directa equivalente (misma lógica que la vista), medida antes de crear la vista, tardó **1192.272 ms**. En el bloque posterior de pruebas:

| Consulta | Tiempo |
|---|---|
| Directa equivalente | 706.310 ms |
| Lectura de la vista materializada | 0.284 ms |

Para la comparación más justa se usa **706.310 ms vs. 0.284 ms**: mejora aproximada de **2487x**. La diferencia entre las dos mediciones de la directa (1192.272 vs. 706.310 ms) muestra variación por caché/ejecución, por lo que **no se debe atribuir toda la variación a cambios de diseño**.

Los **dos EXCEPT de equivalencia** (direcciones A y B, comparando las cuatro columnas) dieron **0 filas** en DBeaver sobre `foodstore_tp5`, confirmando que la vista materializada produce exactamente el mismo resultado que la consulta directa.

## Política de actualización

- Refrescar por lote (cierre mensual) o **diariamente para paneles** de control.
- Usar `REFRESH MATERIALIZED VIEW CONCURRENTLY` cuando haya usuarios leyendo el reporte en paralelo (no bloquea lecturas).
- **Nunca refrescar por cada INSERT**: el costo del refresh (re-ejecuta los cuatro joins sobre toda la tabla) supera el beneficio de mantener el dato en tiempo real.
- La vista puede quedar **desactualizada entre refreshes** y es una instantánea: **no sirve para stock, pedidos activos ni operaciones transaccionales** (esas consultas deben ir a las tablas base).
