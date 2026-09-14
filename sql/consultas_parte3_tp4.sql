-- ============================================================
-- CONSULTAS PARTE 3 — TP4 FoodStore
--
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17).
-- Spec A: ranking de productos por facturación dentro de su
--         categoría (función de ventana RANK).
-- Spec B: pedidos cuyo total supera el promedio personal del
--         usuario (subconsulta correlacionada).
--
-- Cada Spec consta de una consulta principal, una alternativa
-- semánticamente equivalente con estructura distinta y dos
-- verificaciones EXCEPT (una por sentido) que comparan TODAS las
-- columnas de salida. Cada variante conserva su ORDER BY dentro
-- de su CTE antes de compararse.
-- RESULTADO ESPERADO: 0 filas en las cuatro verificaciones y en
-- ambas direcciones. (Este script no afirma haberlas ejecutado.)
-- ============================================================

-- ============================================================
-- SPEC A — CONSULTA 1 (principal)
-- ============================================================
-- Productos vigentes con al menos una venta: unidades vendidas,
-- facturación y puesto (RANK) por facturación descendente dentro
-- de su categoría. Los empates de facturación comparten puesto.
-- Filtros: categoria, producto y detalle_pedido no eliminados.
-- Orden: id_categoria ASC, puesto ASC, id_producto ASC.

SELECT c.id_categoria,
       c.nombre_categoria,
       p.id_producto,
       p.nombre_producto,
       SUM(dp.cantidad) AS unidades_vendidas,
       SUM(dp.subtotal) AS facturacion,
       RANK() OVER (
           PARTITION BY c.id_categoria
           ORDER BY SUM(dp.subtotal) DESC
       ) AS puesto
FROM detalle_pedido dp
JOIN producto p ON p.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE dp.eliminado = FALSE
  AND p.eliminado = FALSE
  AND c.eliminado = FALSE
GROUP BY c.id_categoria, c.nombre_categoria, p.id_producto, p.nombre_producto
ORDER BY c.id_categoria ASC, puesto ASC, p.id_producto ASC;

-- ============================================================
-- SPEC A — ALTERNATIVA 1 (agregación en CTE + ventana externa)
-- ============================================================
-- Iguales filtros, agrupación y métricas; difiere en que la
-- agregación se materializa primero en un CTE y el RANK se calcula
-- después sobre la columna facturacion ya agregada.

WITH facturacion_producto AS (
    SELECT c.id_categoria,
           c.nombre_categoria,
           p.id_producto,
           p.nombre_producto,
           SUM(dp.cantidad) AS unidades_vendidas,
           SUM(dp.subtotal) AS facturacion
    FROM detalle_pedido dp
    JOIN producto p ON p.id_producto = dp.id_producto
    JOIN categoria c ON c.id_categoria = p.id_categoria
    WHERE dp.eliminado = FALSE
      AND p.eliminado = FALSE
      AND c.eliminado = FALSE
    GROUP BY c.id_categoria, c.nombre_categoria, p.id_producto, p.nombre_producto
)
SELECT f.id_categoria,
       f.nombre_categoria,
       f.id_producto,
       f.nombre_producto,
       f.unidades_vendidas,
       f.facturacion,
       RANK() OVER (
           PARTITION BY f.id_categoria
           ORDER BY f.facturacion DESC
       ) AS puesto
FROM facturacion_producto f
ORDER BY f.id_categoria ASC, puesto ASC, f.id_producto ASC;

-- ============================================================
-- VERIFICACIÓN A.1 — filas de la Consulta 1 (Spec A) que no están
-- en la Alternativa 1 (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_a AS (
    SELECT c.id_categoria,
           c.nombre_categoria,
           p.id_producto,
           p.nombre_producto,
           SUM(dp.cantidad) AS unidades_vendidas,
           SUM(dp.subtotal) AS facturacion,
           RANK() OVER (
               PARTITION BY c.id_categoria
               ORDER BY SUM(dp.subtotal) DESC
           ) AS puesto
    FROM detalle_pedido dp
    JOIN producto p ON p.id_producto = dp.id_producto
    JOIN categoria c ON c.id_categoria = p.id_categoria
    WHERE dp.eliminado = FALSE
      AND p.eliminado = FALSE
      AND c.eliminado = FALSE
    GROUP BY c.id_categoria, c.nombre_categoria, p.id_producto, p.nombre_producto
    ORDER BY c.id_categoria ASC, puesto ASC, p.id_producto ASC
),
alternativa_a AS (
    WITH facturacion_producto AS (
        SELECT c.id_categoria,
               c.nombre_categoria,
               p.id_producto,
               p.nombre_producto,
               SUM(dp.cantidad) AS unidades_vendidas,
               SUM(dp.subtotal) AS facturacion
        FROM detalle_pedido dp
        JOIN producto p ON p.id_producto = dp.id_producto
        JOIN categoria c ON c.id_categoria = p.id_categoria
        WHERE dp.eliminado = FALSE
          AND p.eliminado = FALSE
          AND c.eliminado = FALSE
        GROUP BY c.id_categoria, c.nombre_categoria, p.id_producto, p.nombre_producto
    )
    SELECT f.id_categoria,
           f.nombre_categoria,
           f.id_producto,
           f.nombre_producto,
           f.unidades_vendidas,
           f.facturacion,
           RANK() OVER (
               PARTITION BY f.id_categoria
               ORDER BY f.facturacion DESC
           ) AS puesto
    FROM facturacion_producto f
    ORDER BY f.id_categoria ASC, puesto ASC, f.id_producto ASC
)
SELECT id_categoria, nombre_categoria, id_producto, nombre_producto,
       unidades_vendidas, facturacion, puesto
FROM consulta_a
EXCEPT
SELECT id_categoria, nombre_categoria, id_producto, nombre_producto,
       unidades_vendidas, facturacion, puesto
FROM alternativa_a;

-- ============================================================
-- VERIFICACIÓN A.2 — filas de la Alternativa 1 (Spec A) que no
-- están en la Consulta 1 (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_a AS (
    SELECT c.id_categoria,
           c.nombre_categoria,
           p.id_producto,
           p.nombre_producto,
           SUM(dp.cantidad) AS unidades_vendidas,
           SUM(dp.subtotal) AS facturacion,
           RANK() OVER (
               PARTITION BY c.id_categoria
               ORDER BY SUM(dp.subtotal) DESC
           ) AS puesto
    FROM detalle_pedido dp
    JOIN producto p ON p.id_producto = dp.id_producto
    JOIN categoria c ON c.id_categoria = p.id_categoria
    WHERE dp.eliminado = FALSE
      AND p.eliminado = FALSE
      AND c.eliminado = FALSE
    GROUP BY c.id_categoria, c.nombre_categoria, p.id_producto, p.nombre_producto
    ORDER BY c.id_categoria ASC, puesto ASC, p.id_producto ASC
),
alternativa_a AS (
    WITH facturacion_producto AS (
        SELECT c.id_categoria,
               c.nombre_categoria,
               p.id_producto,
               p.nombre_producto,
               SUM(dp.cantidad) AS unidades_vendidas,
               SUM(dp.subtotal) AS facturacion
        FROM detalle_pedido dp
        JOIN producto p ON p.id_producto = dp.id_producto
        JOIN categoria c ON c.id_categoria = p.id_categoria
        WHERE dp.eliminado = FALSE
          AND p.eliminado = FALSE
          AND c.eliminado = FALSE
        GROUP BY c.id_categoria, c.nombre_categoria, p.id_producto, p.nombre_producto
    )
    SELECT f.id_categoria,
           f.nombre_categoria,
           f.id_producto,
           f.nombre_producto,
           f.unidades_vendidas,
           f.facturacion,
           RANK() OVER (
               PARTITION BY f.id_categoria
               ORDER BY f.facturacion DESC
           ) AS puesto
    FROM facturacion_producto f
    ORDER BY f.id_categoria ASC, puesto ASC, f.id_producto ASC
)
SELECT id_categoria, nombre_categoria, id_producto, nombre_producto,
       unidades_vendidas, facturacion, puesto
FROM alternativa_a
EXCEPT
SELECT id_categoria, nombre_categoria, id_producto, nombre_producto,
       unidades_vendidas, facturacion, puesto
FROM consulta_a;

-- ============================================================
-- SPEC B — CONSULTA 2 (principal)
-- ============================================================
-- Pedidos no eliminados cuyo total es estrictamente mayor que el
-- promedio de todos los pedidos no eliminados del mismo usuario.
-- El promedio se calcula con una subconsulta correlacionada por
-- id_usuario (alias interno p2, alias externo ped/u).
-- Orden: total DESC, id_pedido ASC.

SELECT u.id_usuario,
       u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
       ped.id_pedido,
       ped.fecha,
       ped.total,
       (
           SELECT AVG(p2.total)
           FROM pedido p2
           WHERE p2.id_usuario = u.id_usuario
             AND p2.eliminado = FALSE
       ) AS promedio_personal
FROM pedido ped
JOIN usuario u ON u.id_usuario = ped.id_usuario
WHERE ped.eliminado = FALSE
  AND u.eliminado = FALSE
  AND ped.total > (
      SELECT AVG(p2.total)
      FROM pedido p2
      WHERE p2.id_usuario = u.id_usuario
        AND p2.eliminado = FALSE
  )
ORDER BY ped.total DESC, ped.id_pedido ASC;

-- ============================================================
-- SPEC B — ALTERNATIVA 2 (CTE de promedios por usuario + JOIN)
-- ============================================================
-- El promedio por usuario se calcula una sola vez en un CTE
-- (mismos filtros: p2.eliminado = FALSE) y se une por id_usuario;
-- la comparación estricta `>` se hace contra la columna del CTE.

WITH promedio_usuario AS (
    SELECT p2.id_usuario,
           AVG(p2.total) AS promedio_personal
    FROM pedido p2
    WHERE p2.eliminado = FALSE
    GROUP BY p2.id_usuario
)
SELECT u.id_usuario,
       u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
       ped.id_pedido,
       ped.fecha,
       ped.total,
       pu.promedio_personal
FROM pedido ped
JOIN usuario u ON u.id_usuario = ped.id_usuario
JOIN promedio_usuario pu ON pu.id_usuario = u.id_usuario
WHERE ped.eliminado = FALSE
  AND u.eliminado = FALSE
  AND ped.total > pu.promedio_personal
ORDER BY ped.total DESC, ped.id_pedido ASC;

-- ============================================================
-- VERIFICACIÓN B.1 — filas de la Consulta 2 (Spec B) que no están
-- en la Alternativa 2 (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_b AS (
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           ped.id_pedido,
           ped.fecha,
           ped.total,
           (
               SELECT AVG(p2.total)
               FROM pedido p2
               WHERE p2.id_usuario = u.id_usuario
                 AND p2.eliminado = FALSE
           ) AS promedio_personal
    FROM pedido ped
    JOIN usuario u ON u.id_usuario = ped.id_usuario
    WHERE ped.eliminado = FALSE
      AND u.eliminado = FALSE
      AND ped.total > (
          SELECT AVG(p2.total)
          FROM pedido p2
          WHERE p2.id_usuario = u.id_usuario
            AND p2.eliminado = FALSE
      )
    ORDER BY ped.total DESC, ped.id_pedido ASC
),
alternativa_b AS (
    WITH promedio_usuario AS (
        SELECT p2.id_usuario,
               AVG(p2.total) AS promedio_personal
        FROM pedido p2
        WHERE p2.eliminado = FALSE
        GROUP BY p2.id_usuario
    )
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           ped.id_pedido,
           ped.fecha,
           ped.total,
           pu.promedio_personal
    FROM pedido ped
    JOIN usuario u ON u.id_usuario = ped.id_usuario
    JOIN promedio_usuario pu ON pu.id_usuario = u.id_usuario
    WHERE ped.eliminado = FALSE
      AND u.eliminado = FALSE
      AND ped.total > pu.promedio_personal
    ORDER BY ped.total DESC, ped.id_pedido ASC
)
SELECT id_usuario, nombre_completo, id_pedido, fecha, total, promedio_personal
FROM consulta_b
EXCEPT
SELECT id_usuario, nombre_completo, id_pedido, fecha, total, promedio_personal
FROM alternativa_b;

-- ============================================================
-- VERIFICACIÓN B.2 — filas de la Alternativa 2 (Spec B) que no
-- están en la Consulta 2 (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_b AS (
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           ped.id_pedido,
           ped.fecha,
           ped.total,
           (
               SELECT AVG(p2.total)
               FROM pedido p2
               WHERE p2.id_usuario = u.id_usuario
                 AND p2.eliminado = FALSE
           ) AS promedio_personal
    FROM pedido ped
    JOIN usuario u ON u.id_usuario = ped.id_usuario
    WHERE ped.eliminado = FALSE
      AND u.eliminado = FALSE
      AND ped.total > (
          SELECT AVG(p2.total)
          FROM pedido p2
          WHERE p2.id_usuario = u.id_usuario
            AND p2.eliminado = FALSE
      )
    ORDER BY ped.total DESC, ped.id_pedido ASC
),
alternativa_b AS (
    WITH promedio_usuario AS (
        SELECT p2.id_usuario,
               AVG(p2.total) AS promedio_personal
        FROM pedido p2
        WHERE p2.eliminado = FALSE
        GROUP BY p2.id_usuario
    )
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           ped.id_pedido,
           ped.fecha,
           ped.total,
           pu.promedio_personal
    FROM pedido ped
    JOIN usuario u ON u.id_usuario = ped.id_usuario
    JOIN promedio_usuario pu ON pu.id_usuario = u.id_usuario
    WHERE ped.eliminado = FALSE
      AND u.eliminado = FALSE
      AND ped.total > pu.promedio_personal
    ORDER BY ped.total DESC, ped.id_pedido ASC
)
SELECT id_usuario, nombre_completo, id_pedido, fecha, total, promedio_personal
FROM alternativa_b
EXCEPT
SELECT id_usuario, nombre_completo, id_pedido, fecha, total, promedio_personal
FROM consulta_b;