-- ============================================================
-- ÍNDICES — TP5 FoodStore (Parte A)
--
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17).
-- Tres CREATE INDEX parciales, uno por consulta seleccionada.
-- Cada sección documenta: la consulta objetivo, el plan previo
-- observado (EXPLAIN ANALYZE real) y la expectativa a validar
-- luego con EXPLAIN ANALYZE (hipótesis, no resultado garantizado).
--
-- Sin IF NOT EXISTS, sin DROP INDEX, sin CONCURRENTLY, sin INCLUDE,
-- sin extensiones y sin cambios de esquema.
-- ============================================================

-- ============================================================
-- 1. Pedidos cancelados — índice parcial por fecha y estado
-- ============================================================
-- Consulta objetivo: pedidos cancelados y vigentes, sin rango de
-- fechas: el filtro es exactamente estado = 'CANCELADO'.
--
--   SELECT ped.id_pedido, ped.fecha, ped.estado, ped.forma_pago,
--          ped.total
--   FROM   pedido ped
--   WHERE  ped.estado = 'CANCELADO'
--     AND  ped.eliminado = FALSE
--   ORDER  BY ped.fecha DESC;
--
-- Plan previo observado:
--   Parallel Seq Scan sobre pedido; 1 fila encontrada y
--   aproximadamente 200.000 filas evaluadas.
--   Execution Time: 210.677 ms.
--
-- Selectividad: eliminado = FALSE por sí solo no es selectivo en
-- esta base (la casi totalidad de los pedidos son vigentes). La
-- selectividad real surge del índice parcial, que contiene
-- únicamente pedidos vigentes cancelados; el filtro de estado queda
-- aplicado por la condición del índice, no como filtro posterior.
--
-- Expectativa a validar con EXPLAIN ANALYZE: que el nodo de acceso
-- pase a Index Scan o Bitmap Index Scan usando este índice, que
-- desaparezca o se reduzca el Rows Removed by Filter por estado
-- sobre el historial, y que el Execution Time baje respecto de
-- 210.677 ms. Es una hipótesis: si la fracción de cancelados es
-- alta, el planner podría seguir prefiriendo Seq Scan y el índice
-- se documentaría como descartado.

CREATE INDEX idx_pedido_cancelado_fecha_vig
ON pedido (fecha DESC)
WHERE eliminado = FALSE
  AND estado = 'CANCELADO';

-- ============================================================
-- 2. Productos no disponibles — índice parcial por nombre
-- ============================================================
-- Consulta objetivo: productos no disponibles, ordenados por nombre
-- ascendente (para stock/gestión); no filtra por patrón ni prefijo.
--
--   SELECT id_producto, nombre_producto, precio, stock
--   FROM   producto
--   WHERE  disponible = FALSE
--   ORDER  BY nombre_producto ASC;
--
-- Plan previo observado:
--   Seq Scan sobre producto; 1 fila encontrada y 50.024 filas
--   descartadas.
--   Execution Time: 31.581 ms.
--
-- Expectativa a validar con EXPLAIN ANALYZE: que el Seq Scan pase a
-- Index Scan usando este índice (solo índices las filas no
-- disponibles y no eliminadas), que desaparezca el descarte de las
-- ~50.024 filas por disponible/eliminado, y que el Execution Time
-- baje respecto de 31.581 ms. Es una hipótesis: depende del volumen
-- de productos no disponibles en la base (la condición
-- disponible = FALSE ya delimita el índice parcial).

CREATE INDEX idx_producto_no_disponible_nombre_vig
ON producto (nombre_producto ASC)
WHERE eliminado = FALSE
  AND disponible = FALSE;

-- ============================================================
-- 3. Detalles con cantidad excepcional — índice parcial por cantidad
-- ============================================================
-- Consulta objetivo: detalles vigentes con cantidad alta (>= 5),
-- que representan pedidos inusuales (control o auditoría).
--
--   SELECT id_detalle, id_pedido, id_producto, cantidad, subtotal
--   FROM   detalle_pedido
--   WHERE  eliminado = FALSE
--     AND  cantidad >= 5
--   ORDER  BY cantidad DESC, id_detalle ASC;
--
-- Plan previo observado:
--   Parallel Seq Scan sobre detalle_pedido; 3 filas encontradas y
--   aproximadamente 400.000 filas evaluadas.
--   Execution Time: 182.874 ms.
--
-- Expectativa a validar con EXPLAIN ANALYZE: que el acceso pase a
-- Index Scan usando este índice (solo las filas con cantidad >= 5 y
-- no eliminadas), que las ~400.000 filas evaluadas se reduzcan a las
-- pocas filas del resultado, y que el Execution Time baje respecto de
-- 182.874 ms. Es una hipótesis: por la alta selectividad esperada
-- (cantidad >= 5 es raro), el planner debería preferir el índice.

CREATE INDEX idx_detalle_cantidad_excepcional_vig
ON detalle_pedido (cantidad DESC, id_detalle ASC)
WHERE eliminado = FALSE
  AND cantidad >= 5;