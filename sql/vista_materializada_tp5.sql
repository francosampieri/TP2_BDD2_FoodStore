-- ============================================================
-- VISTA MATERIALIZADA TP5 — FoodStore (Parte C)
--
-- Base de ejecución documentada: foodstore_tp5 (PostgreSQL 17).
-- Una única vista materializada de facturación por categoría y
-- mes, definida según specs/vista_materializada_tp5.md.
--
-- Objetivo: precomputar la agregación de facturación (detalle_pedido
-- JOIN pedido JOIN producto JOIN categoria) para que cada lectura del
-- reporte lea una tabla pequeña y ya resuelta en lugar de repetir los
-- cuatro joins y el sort de disco (referencia base TP4: 946.611 ms).
--
-- Instantánea de datos: la vista es una imagen del estado de la base
-- en el momento del último REFRESH. No refleja cambios posteriores y
-- no debe usarse para operaciones en tiempo real (totales de pedido
-- activos, stock, decisiones transaccionales); su rol es exclusivamente
-- reporte analítico histórico. Se pobla ahora con WITH DATA.
--
-- Sin DROP, sin IF NOT EXISTS, sin CONCURRENTLY, sin extensiones y
-- sin cambios sobre tablas existentes.
-- ============================================================

CREATE MATERIALIZED VIEW mv_tp5_facturacion_categoria_mes
AS
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
WITH DATA;

-- ============================================================
-- Índice único sobre (id_categoria, mes)
-- ============================================================
-- La agrupación garantiza exactamente una fila por par
-- (id_categoria, mes), por lo que esta combinación es la clave
-- natural del resultado. El índice único:
--   - habilita futuros REFRESH MATERIALIZED VIEW CONCURRENTLY
--     (requisito: al menos un índice único sobre las columnas que
--     identifican unívocamente cada fila);
--   - se define sobre id_categoria (entero) en lugar de
--     nombre_categoria (texto): más compacto, más rápido de comparar
--     y estable ante renombres de categoría;
--   - sobre mes (TIMESTAMPTZ) permite además consultas de rango
--     temporal eficientes sobre la vista materializada.

CREATE UNIQUE INDEX uq_mv_tp5_facturacion_categoria_mes
ON mv_tp5_facturacion_categoria_mes (id_categoria, mes);