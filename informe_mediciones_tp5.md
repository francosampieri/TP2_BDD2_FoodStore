# Informe de Mediciones — TP5 FoodStore (Parte A)

Base de trabajo: `foodstore_tp3` y `foodstore_tp5` (PostgreSQL 17). Medición manual en DBeaver. Los tiempos de lectura provienen de `EXPLAIN ANALYZE` (se toma el `Execution Time`).

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