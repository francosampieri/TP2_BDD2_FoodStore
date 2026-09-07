-- ============================================================
-- ÍNDICES DE OPTIMIZACIÓN — TP3 FoodStore (Parte 2)
--
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17).
--
-- LOS TRES ÍNDICES PROPUESTOS SE PROBARON CON EXPLAIN ANALYZE REAL
-- (post ANALYZE) y solo uno superó la validación por Execution Time:
--
--   * idx_producto_cat_precio_vig        (Q1) -> DESCARTADO, no mejoró el
--     Execution Time (7.744 ms antes vs 57.370 ms después). El plan
--     siguió usando Bitmap Heap Scan + Sort.
--   * idx_pedido_fecha_conf_vig          (Q2) -> DESCARTADO, no mejoró el
--     Execution Time (182.260 ms antes vs 288.887 ms después). El plan
--     siguió usando Bitmap Heap Scan + Sort.
--   * idx_detalle_pedido_producto_vig    (Q3) -> ACEPTADO: el plan pasó de
--     Parallel Seq Scan a Index Scan sobre este índice (406.794 ms antes
--     vs 16.355 ms después; mejora ~25x).
-- ============================================================

-- Optimiza Q3: detalles vigentes de un producto (p. ej. TP3_Producto_1)
-- con su pedido, ordenados por fecha DESC.
-- Nodo esperado a mejorar (validado en ejecución): reemplazar el
-- barrido paralelo de la tabla para devolver 8 filas por un Index Scan
-- sobre este índice parcial por id_producto.
CREATE INDEX idx_detalle_pedido_producto_vig
ON detalle_pedido (id_producto)
WHERE eliminado = FALSE;