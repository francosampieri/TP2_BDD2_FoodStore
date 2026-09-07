-- ============================================================
-- CONSULTAS PARTE 4 — TP3 FoodStore
--
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17).
-- Consulta A / Alternativa A y Consulta B / Alternativa B deben
-- producir exactamente el mismo conjunto de filas (mismas columnas,
-- mismos filtros, mismo orden y mismo LIMIT).
--
-- Verificación formal con EXCEPT (cuatro verificaciones):
--   1) (Consulta A - Alternativa A): filas de A que no están en AltA.
--   2) (Alternativa A - Consulta A): filas de AltA que no están en A.
--   3) (Consulta B - Alternativa B): filas de B que no están en AltB.
--   4) (Alternativa B - Consulta B): filas de AltB que no están en B.
-- Cada verificación compara TODAS las columnas del resultado y cada
-- variante conserva su ORDER BY y LIMIT dentro de su CTE/subconsulta
-- antes de compararse.
-- RESULTADO REAL: las cuatro verificaciones devolvieron 0 filas en
-- cada dirección.
-- ============================================================

-- ============================================================
-- CONSULTA A — resumen/agregación sobre usuario y pedido
-- ============================================================
-- Usuarios vigentes con sus pedidos TERMINADO de los últimos 90 días.
-- Incluye usuarios sin pedidos válidos (cantidad y gasto en 0).
-- Orden: gasto DESC, cantidad DESC, id_usuario ASC. Límite 20.

SELECT u.id_usuario,
       u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
       COUNT(p.id_pedido) AS cantidad_pedidos,
       COALESCE(SUM(p.total), 0) AS gasto_total
FROM usuario u
LEFT JOIN pedido p
       ON p.id_usuario = u.id_usuario
      AND p.eliminado = FALSE
      AND p.estado = 'TERMINADO'
      AND p.fecha >= CURRENT_DATE - 90
WHERE u.eliminado = FALSE
GROUP BY u.id_usuario, u.nombre_usuario, u.apellido
ORDER BY gasto_total DESC, cantidad_pedidos DESC, u.id_usuario ASC
LIMIT 20;

-- ============================================================
-- ALTERNATIVA A — agrupación previa en CTE + LEFT JOIN contra usuario
-- ============================================================

WITH resumen_pedidos AS (
    SELECT p.id_usuario,
           COUNT(*) AS cantidad_pedidos,
           COALESCE(SUM(p.total), 0) AS gasto_total
    FROM pedido p
    WHERE p.eliminado = FALSE
      AND p.estado = 'TERMINADO'
      AND p.fecha >= CURRENT_DATE - 90
    GROUP BY p.id_usuario
)
SELECT u.id_usuario,
       u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
       COALESCE(r.cantidad_pedidos, 0) AS cantidad_pedidos,
       COALESCE(r.gasto_total, 0) AS gasto_total
FROM usuario u
LEFT JOIN resumen_pedidos r ON r.id_usuario = u.id_usuario
WHERE u.eliminado = FALSE
ORDER BY gasto_total DESC, cantidad_pedidos DESC, u.id_usuario ASC
LIMIT 20;

-- ============================================================
-- CONSULTA B — subconsulta correlacionada sobre producto y categoria
-- ============================================================
-- Productos vigentes y disponibles con precio estrictamente mayor al
-- promedio de su misma categoría (subconsulta correlacionada).
-- Orden: nombre_categoria ASC, precio DESC, id_producto ASC. Límite 30.

SELECT pr.id_producto,
       pr.nombre_producto,
       c.nombre_categoria,
       pr.precio
FROM producto pr
JOIN categoria c ON c.id_categoria = pr.id_categoria
WHERE pr.eliminado = FALSE
  AND pr.disponible = TRUE
  AND c.eliminado = FALSE
  AND pr.precio > (
      SELECT AVG(p2.precio)
      FROM producto p2
      WHERE p2.id_categoria = pr.id_categoria
        AND p2.eliminado = FALSE
        AND p2.disponible = TRUE
  )
ORDER BY c.nombre_categoria ASC, pr.precio DESC, pr.id_producto ASC
LIMIT 30;

-- ============================================================
-- ALTERNATIVA B — AVG por categoría en CTE + JOIN
-- ============================================================

WITH precio_promedio_categoria AS (
    SELECT p2.id_categoria,
           AVG(p2.precio) AS precio_promedio
    FROM producto p2
    WHERE p2.eliminado = FALSE
      AND p2.disponible = TRUE
    GROUP BY p2.id_categoria
)
SELECT pr.id_producto,
       pr.nombre_producto,
       c.nombre_categoria,
       pr.precio
FROM producto pr
JOIN categoria c ON c.id_categoria = pr.id_categoria
JOIN precio_promedio_categoria pp ON pp.id_categoria = pr.id_categoria
WHERE pr.eliminado = FALSE
  AND pr.disponible = TRUE
  AND c.eliminado = FALSE
  AND pr.precio > pp.precio_promedio
ORDER BY c.nombre_categoria ASC, pr.precio DESC, pr.id_producto ASC
LIMIT 30;

-- ============================================================
-- VERIFICACIÓN FORMAL 1 — filas de Consulta A que no están en
-- Alternativa A (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_a AS (
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           COUNT(p.id_pedido) AS cantidad_pedidos,
           COALESCE(SUM(p.total), 0) AS gasto_total
    FROM usuario u
    LEFT JOIN pedido p
           ON p.id_usuario = u.id_usuario
          AND p.eliminado = FALSE
          AND p.estado = 'TERMINADO'
          AND p.fecha >= CURRENT_DATE - 90
    WHERE u.eliminado = FALSE
    GROUP BY u.id_usuario, u.nombre_usuario, u.apellido
    ORDER BY gasto_total DESC, cantidad_pedidos DESC, u.id_usuario ASC
    LIMIT 20
),
alternativa_a AS (
    WITH resumen_pedidos AS (
        SELECT p.id_usuario,
               COUNT(*) AS cantidad_pedidos,
               COALESCE(SUM(p.total), 0) AS gasto_total
        FROM pedido p
        WHERE p.eliminado = FALSE
          AND p.estado = 'TERMINADO'
          AND p.fecha >= CURRENT_DATE - 90
        GROUP BY p.id_usuario
    )
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           COALESCE(r.cantidad_pedidos, 0) AS cantidad_pedidos,
           COALESCE(r.gasto_total, 0) AS gasto_total
    FROM usuario u
    LEFT JOIN resumen_pedidos r ON r.id_usuario = u.id_usuario
    WHERE u.eliminado = FALSE
    ORDER BY gasto_total DESC, cantidad_pedidos DESC, u.id_usuario ASC
    LIMIT 20
)
SELECT id_usuario, nombre_completo, cantidad_pedidos, gasto_total
FROM consulta_a
EXCEPT
SELECT id_usuario, nombre_completo, cantidad_pedidos, gasto_total
FROM alternativa_a;

-- ============================================================
-- VERIFICACIÓN FORMAL 2 — filas de Alternativa A que no están en
-- Consulta A (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_a AS (
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           COUNT(p.id_pedido) AS cantidad_pedidos,
           COALESCE(SUM(p.total), 0) AS gasto_total
    FROM usuario u
    LEFT JOIN pedido p
           ON p.id_usuario = u.id_usuario
          AND p.eliminado = FALSE
          AND p.estado = 'TERMINADO'
          AND p.fecha >= CURRENT_DATE - 90
    WHERE u.eliminado = FALSE
    GROUP BY u.id_usuario, u.nombre_usuario, u.apellido
    ORDER BY gasto_total DESC, cantidad_pedidos DESC, u.id_usuario ASC
    LIMIT 20
),
alternativa_a AS (
    WITH resumen_pedidos AS (
        SELECT p.id_usuario,
               COUNT(*) AS cantidad_pedidos,
               COALESCE(SUM(p.total), 0) AS gasto_total
        FROM pedido p
        WHERE p.eliminado = FALSE
          AND p.estado = 'TERMINADO'
          AND p.fecha >= CURRENT_DATE - 90
        GROUP BY p.id_usuario
    )
    SELECT u.id_usuario,
           u.nombre_usuario || ' ' || u.apellido AS nombre_completo,
           COALESCE(r.cantidad_pedidos, 0) AS cantidad_pedidos,
           COALESCE(r.gasto_total, 0) AS gasto_total
    FROM usuario u
    LEFT JOIN resumen_pedidos r ON r.id_usuario = u.id_usuario
    WHERE u.eliminado = FALSE
    ORDER BY gasto_total DESC, cantidad_pedidos DESC, u.id_usuario ASC
    LIMIT 20
)
SELECT id_usuario, nombre_completo, cantidad_pedidos, gasto_total
FROM alternativa_a
EXCEPT
SELECT id_usuario, nombre_completo, cantidad_pedidos, gasto_total
FROM consulta_a;

-- ============================================================
-- VERIFICACIÓN FORMAL 3 — filas de Consulta B que no están en
-- Alternativa B (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_b AS (
    SELECT pr.id_producto,
           pr.nombre_producto,
           c.nombre_categoria,
           pr.precio
    FROM producto pr
    JOIN categoria c ON c.id_categoria = pr.id_categoria
    WHERE pr.eliminado = FALSE
      AND pr.disponible = TRUE
      AND c.eliminado = FALSE
      AND pr.precio > (
          SELECT AVG(p2.precio)
          FROM producto p2
          WHERE p2.id_categoria = pr.id_categoria
            AND p2.eliminado = FALSE
            AND p2.disponible = TRUE
      )
    ORDER BY c.nombre_categoria ASC, pr.precio DESC, pr.id_producto ASC
    LIMIT 30
),
alternativa_b AS (
    WITH precio_promedio_categoria AS (
        SELECT p2.id_categoria,
               AVG(p2.precio) AS precio_promedio
        FROM producto p2
        WHERE p2.eliminado = FALSE
          AND p2.disponible = TRUE
        GROUP BY p2.id_categoria
    )
    SELECT pr.id_producto,
           pr.nombre_producto,
           c.nombre_categoria,
           pr.precio
    FROM producto pr
    JOIN categoria c ON c.id_categoria = pr.id_categoria
    JOIN precio_promedio_categoria pp ON pp.id_categoria = pr.id_categoria
    WHERE pr.eliminado = FALSE
      AND pr.disponible = TRUE
      AND c.eliminado = FALSE
      AND pr.precio > pp.precio_promedio
    ORDER BY c.nombre_categoria ASC, pr.precio DESC, pr.id_producto ASC
    LIMIT 30
)
SELECT id_producto, nombre_producto, nombre_categoria, precio
FROM consulta_b
EXCEPT
SELECT id_producto, nombre_producto, nombre_categoria, precio
FROM alternativa_b;

-- ============================================================
-- VERIFICACIÓN FORMAL 4 — filas de Alternativa B que no están en
-- Consulta B (TODAS las columnas; esperado: 0 filas)
-- ============================================================

WITH consulta_b AS (
    SELECT pr.id_producto,
           pr.nombre_producto,
           c.nombre_categoria,
           pr.precio
    FROM producto pr
    JOIN categoria c ON c.id_categoria = pr.id_categoria
    WHERE pr.eliminado = FALSE
      AND pr.disponible = TRUE
      AND c.eliminado = FALSE
      AND pr.precio > (
          SELECT AVG(p2.precio)
          FROM producto p2
          WHERE p2.id_categoria = pr.id_categoria
            AND p2.eliminado = FALSE
            AND p2.disponible = TRUE
      )
    ORDER BY c.nombre_categoria ASC, pr.precio DESC, pr.id_producto ASC
    LIMIT 30
),
alternativa_b AS (
    WITH precio_promedio_categoria AS (
        SELECT p2.id_categoria,
               AVG(p2.precio) AS precio_promedio
        FROM producto p2
        WHERE p2.eliminado = FALSE
          AND p2.disponible = TRUE
        GROUP BY p2.id_categoria
    )
    SELECT pr.id_producto,
           pr.nombre_producto,
           c.nombre_categoria,
           pr.precio
    FROM producto pr
    JOIN categoria c ON c.id_categoria = pr.id_categoria
    JOIN precio_promedio_categoria pp ON pp.id_categoria = pr.id_categoria
    WHERE pr.eliminado = FALSE
      AND pr.disponible = TRUE
      AND c.eliminado = FALSE
      AND pr.precio > pp.precio_promedio
    ORDER BY c.nombre_categoria ASC, pr.precio DESC, pr.id_producto ASC
    LIMIT 30
)
SELECT id_producto, nombre_producto, nombre_categoria, precio
FROM alternativa_b
EXCEPT
SELECT id_producto, nombre_producto, nombre_categoria, precio
FROM consulta_b;