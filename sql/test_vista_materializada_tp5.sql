-- ============================================================
-- TEST DE LECTURA VISTA MATERIALIZADA TP5 — FoodStore (Parte C)
--
-- Base de ejecución documentada: foodstore_tp5 (PostgreSQL 17).
-- Requiere haber creado y poblado mv_tp5_facturacion_categoria_mes
-- (sql/vista_materializada_tp5.sql).
--
-- Solo consultas de lectura: no INSERT/UPDATE/DELETE y sin DDL.
-- Incluye EXPLAIN ANALYZE (solo SELECT, no modifica datos).
-- ============================================================

-- ============================================================
-- 1. Consulta directa equivalente (base de medición)
-- ============================================================
-- Misma lógica que la vista materializada: agrega todo
-- detalle_pedido vigente con pedido vigente, sin filtrar producto
-- ni categoria (clasificación histórica de facturación real).

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
ORDER  BY mes ASC, facturado DESC;

-- ============================================================
-- 2. Lectura sobre la vista materializada
-- ============================================================
-- Debe producir exactamente el mismo resultado que la consulta
-- directa, en el mismo orden.

SELECT id_categoria,
       nombre_categoria,
       mes,
       facturado
FROM   mv_tp5_facturacion_categoria_mes
ORDER  BY mes ASC, facturado DESC;

-- ============================================================
-- 3. EXPLAIN ANALYZE — registrar los tiempos reales aqui
-- ============================================================

-- 3.1 Consulta directa equivalente.
--     Tiempo de referencia TP4 (foodstore_tp3): 946.611 ms.
--     Tiempo real registrado en DBeaver sobre foodstore_tp5:
--     [completar: ____ ms]
EXPLAIN ANALYZE
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
ORDER  BY mes ASC, facturado DESC;

-- 3.2 Lectura sobre la vista materializada.
--     Esperado: Seq Scan sobre la tabla precomputada, sin los
--     cuatro joins ni el sort de disco de la directa.
--     Tiempo real registrado en DBeaver sobre foodstore_tp5:
--     [completar: ____ ms]
EXPLAIN ANALYZE
SELECT id_categoria,
       nombre_categoria,
       mes,
       facturado
FROM   mv_tp5_facturacion_categoria_mes
ORDER  BY mes ASC, facturado DESC;

-- ============================================================
-- 4. Verificación de equivalencia (EXCEPT en ambas direcciones)
-- ============================================================
-- Compara las cuatro columnas completas (id_categoria,
-- nombre_categoria, mes, facturado). Resultado esperado en las
-- dos verificaciones: 0 filas.

-- 4.1 Dirección A — filas en la consulta directa que no están en
--     la vista materializada. Resultado esperado: 0 filas.
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

-- 4.2 Dirección B — filas en la vista materializada que no están
--     en la consulta directa. Resultado esperado: 0 filas.
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

-- ============================================================
-- 5. Ejemplo de actualización (NO debe ejecutarse aquí)
-- ============================================================
-- REFRESH CONCURRENTLY no bloquea lecturas: la vista sigue
-- respondiendo con los datos anteriores mientras se refresca.
-- Requiere el índice único uq_mv_tp5_facturacion_categoria_mes
-- (creado en sql/vista_materializada_tp5.sql), que identifica
-- unívocamente cada fila por (id_categoria, mes).
--
-- Ejecutar manualmente cuando se desee actualizar la instantánea
-- (p. ej., cierre mensual o demo). El texto está comentado a
-- propósito para que este archivo de verificación no lo dispare:
--
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tp5_facturacion_categoria_mes;