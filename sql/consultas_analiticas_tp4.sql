-- ============================================================
-- CONSULTAS ANALÍTICAS — TP4 FoodStore (Parte 1)
--
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17).
-- Contiene las DOS consultas originales medidas en la Parte 1 y
-- las reescrituras probadas con EXPLAIN ANALYZE para comparación.
--
-- Resultados reales documentados (ver informe_tp4.md):
--   Facturación : original 946,611 ms -> reescritura 1089,669 ms
--   Ranking     : original 1283,410 ms -> reescritura 2599,644 ms
-- Ambas reescrituras fueron DESCARTADAS por empeorar el tiempo
-- real; las consultas originales se mantienen en producción.
--
-- Sin DDL y sin índices: solo consultas (SELECT).
-- ============================================================

-- ============================================================
-- 1.1 CONSULTA ORIGINAL — Facturación por categoría y mes
-- ============================================================
-- Groups by nombre_categoria (texto ancho); plan: Parallel Hash
-- Join detalle_pedido-pedido, Hash Join con producto, Hash Join
-- con categoria, y Sort external merge (4.5-4.8 MB de disco por
-- proceso) antes del Partial GroupAggregate.
-- Execution Time: 946,611 ms.

SELECT c.nombre_categoria AS categoria,
       date_trunc('month', ped.fecha) AS mes,
       SUM(dp.subtotal) AS facturado
FROM detalle_pedido dp
JOIN pedido ped ON ped.id_pedido = dp.id_pedido
               AND ped.eliminado = FALSE
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
WHERE dp.eliminado = FALSE
GROUP BY c.nombre_categoria, date_trunc('month', ped.fecha)
ORDER BY mes, facturado DESC;

-- ============================================================
-- 1.2 REESCRITURA PROBADA — Facturación agrupando por id_categoria
-- ============================================================
-- Agrupa por la clave numérica pr.id_categoria y une categoria al
-- final solo para resolver el rótulo (nombre UNIQUE => 1:1 con el
-- id). El planner eligió Partial HashAggregate en memoria (sin
-- sort previo), pero el tiempo real empeoró.
-- Execution Time: 1089,669 ms.
-- Decisión: DESCARTADA (no conviene mantenerla).

WITH facturacion AS (
    SELECT pr.id_categoria,
           date_trunc('month', ped.fecha) AS mes,
           SUM(dp.subtotal) AS facturado
    FROM detalle_pedido dp
    JOIN pedido ped ON ped.id_pedido = dp.id_pedido
                   AND ped.eliminado = FALSE
    JOIN producto pr ON pr.id_producto = dp.id_producto
    WHERE dp.eliminado = FALSE
    GROUP BY pr.id_categoria, date_trunc('month', ped.fecha)
)
SELECT c.nombre_categoria AS categoria,
       f.mes,
       f.facturado
FROM facturacion f
JOIN categoria c ON c.id_categoria = f.id_categoria
ORDER BY f.mes, f.facturado DESC;

-- ============================================================
-- 2.1 CONSULTA ORIGINAL — Ranking de usuarios por gasto (subtotales)
-- ============================================================
-- Joins Hash detalle_pedido-pedido y pedido-usuario. El
-- COUNT(DISTINCT ped.id_pedido) sobre el join con detalle_pedido
-- obliga a ordenar ~400.000 filas: Sort external merge de
-- 29.416 kB en disco antes del GroupAggregate.
-- Execution Time: 1283,410 ms.

SELECT u.id_usuario,
       u.nombre_usuario || ' ' || u.apellido AS usuario,
       COUNT(DISTINCT ped.id_pedido) AS pedidos,
       SUM(dp.cantidad) AS unidades,
       SUM(dp.subtotal) AS gasto,
       RANK() OVER (ORDER BY SUM(dp.subtotal) DESC) AS puesto
FROM pedido ped
JOIN usuario u ON u.id_usuario = ped.id_usuario
JOIN detalle_pedido dp ON dp.id_pedido = ped.id_pedido
                       AND dp.eliminado = FALSE
WHERE ped.eliminado = FALSE
  AND u.eliminado = FALSE
GROUP BY u.id_usuario, u.nombre_usuario, u.apellido
ORDER BY puesto, u.id_usuario;

-- ============================================================
-- 2.2 REESCRITURA PROBADA — Preagregación de detalles por pedido
-- ============================================================
-- Pre-agrega detalle_pedido por id_pedido antes de unir a usuario,
-- con lo que cada pedido pesa una fila y el COUNT(DISTINCT) se
-- vuelve un COUNT simple. El plan generó dos HashAggregate que
-- usaron batches y disco (pedido: 41 batches, 15.832 kB; usuario:
-- 5 batches, 11.080 kB) y el tiempo real empeoró.
-- Execution Time: 2599,644 ms.
-- Decisión: DESCARTADA (no conviene mantenerla).

WITH detalle_por_pedido AS (
    SELECT dp.id_pedido,
           SUM(dp.subtotal) AS subtotal_pedido,
           SUM(dp.cantidad) AS unidades
    FROM detalle_pedido dp
    WHERE dp.eliminado = FALSE
    GROUP BY dp.id_pedido
)
SELECT u.id_usuario,
       u.nombre_usuario || ' ' || u.apellido AS usuario,
       COUNT(d.id_pedido) AS pedidos,
       SUM(d.unidades) AS unidades,
       SUM(d.subtotal_pedido) AS gasto,
       RANK() OVER (ORDER BY SUM(d.subtotal_pedido) DESC) AS puesto
FROM pedido ped
JOIN usuario u ON u.id_usuario = ped.id_usuario
JOIN detalle_por_pedido d ON d.id_pedido = ped.id_pedido
WHERE ped.eliminado = FALSE
  AND u.eliminado = FALSE
GROUP BY u.id_usuario, u.nombre_usuario, u.apellido
ORDER BY puesto, u.id_usuario;