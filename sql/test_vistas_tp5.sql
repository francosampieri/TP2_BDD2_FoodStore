-- ============================================================
-- TEST DE LECTURA VISTAS TP5 — FoodStore (Parte B)
--
-- Base de ejecución documentada: foodstore_tp5 (PostgreSQL 17).
-- Únicamente consultas de verificación de lectura: no INSERT,
-- no UPDATE, no DELETE y sin DDL.
-- Patrón: dos EXCEPT por vista — la vista menos la consulta
-- manual equivalente y su inversa — comparando TODAS las columnas
-- expuestas. Resultado esperado en cada verificación: 0 filas.
-- Las CTE aplican ORDER BY a ambas ramas para una comparación
-- estable del resultado completo.
-- ============================================================

-- ============================================================
-- Vista 1 — v_tp5_productos_categoria
-- ============================================================

-- V1.1 — Filas de la vista que no están en la consulta manual
--       equivalente. Resultado esperado: 0 filas.
WITH vista AS (
    SELECT id_producto, nombre_producto, precio, stock, disponible,
           id_categoria, nombre_categoria
    FROM   v_tp5_productos_categoria
    ORDER  BY id_categoria, id_producto
),
manual AS (
    SELECT p.id_producto,
           p.nombre_producto,
           p.precio,
           p.stock,
           p.disponible,
           c.id_categoria,
           c.nombre_categoria
    FROM   producto  p
    JOIN   categoria c ON c.id_categoria = p.id_categoria
    WHERE  p.eliminado = FALSE
      AND  c.eliminado = FALSE
    ORDER  BY c.id_categoria, p.id_producto
)
SELECT id_producto, nombre_producto, precio, stock, disponible,
       id_categoria, nombre_categoria
FROM   vista
EXCEPT
SELECT id_producto, nombre_producto, precio, stock, disponible,
       id_categoria, nombre_categoria
FROM   manual;

-- V1.2 — Filas de la consulta manual equivalente que no están en
--       la vista. Resultado esperado: 0 filas.
WITH vista AS (
    SELECT id_producto, nombre_producto, precio, stock, disponible,
           id_categoria, nombre_categoria
    FROM   v_tp5_productos_categoria
    ORDER  BY id_categoria, id_producto
),
manual AS (
    SELECT p.id_producto,
           p.nombre_producto,
           p.precio,
           p.stock,
           p.disponible,
           c.id_categoria,
           c.nombre_categoria
    FROM   producto  p
    JOIN   categoria c ON c.id_categoria = p.id_categoria
    WHERE  p.eliminado = FALSE
      AND  c.eliminado = FALSE
    ORDER  BY c.id_categoria, p.id_producto
)
SELECT id_producto, nombre_producto, precio, stock, disponible,
       id_categoria, nombre_categoria
FROM   manual
EXCEPT
SELECT id_producto, nombre_producto, precio, stock, disponible,
       id_categoria, nombre_categoria
FROM   vista;

-- ============================================================
-- Vista 2 — v_tp5_pedidos_usuario
-- ============================================================

-- V2.1 — Filas de la vista que no están en la consulta manual
--       equivalente. Resultado esperado: 0 filas.
WITH vista AS (
    SELECT id_pedido, fecha, estado, forma_pago, total,
           id_usuario, nombre_usuario, apellido, mail
    FROM   v_tp5_pedidos_usuario
    ORDER  BY id_pedido
),
manual AS (
    SELECT ped.id_pedido,
           ped.fecha,
           ped.estado,
           ped.forma_pago,
           ped.total,
           u.id_usuario,
           u.nombre_usuario,
           u.apellido,
           u.mail
    FROM   pedido  ped
    JOIN   usuario u ON u.id_usuario = ped.id_usuario
    WHERE  ped.eliminado = FALSE
      AND  u.eliminado   = FALSE
    ORDER  BY ped.id_pedido
)
SELECT id_pedido, fecha, estado, forma_pago, total,
       id_usuario, nombre_usuario, apellido, mail
FROM   vista
EXCEPT
SELECT id_pedido, fecha, estado, forma_pago, total,
       id_usuario, nombre_usuario, apellido, mail
FROM   manual;

-- V2.2 — Filas de la consulta manual equivalente que no están en
--       la vista. Resultado esperado: 0 filas.
WITH vista AS (
    SELECT id_pedido, fecha, estado, forma_pago, total,
           id_usuario, nombre_usuario, apellido, mail
    FROM   v_tp5_pedidos_usuario
    ORDER  BY id_pedido
),
manual AS (
    SELECT ped.id_pedido,
           ped.fecha,
           ped.estado,
           ped.forma_pago,
           ped.total,
           u.id_usuario,
           u.nombre_usuario,
           u.apellido,
           u.mail
    FROM   pedido  ped
    JOIN   usuario u ON u.id_usuario = ped.id_usuario
    WHERE  ped.eliminado = FALSE
      AND  u.eliminado   = FALSE
    ORDER  BY ped.id_pedido
)
SELECT id_pedido, fecha, estado, forma_pago, total,
       id_usuario, nombre_usuario, apellido, mail
FROM   manual
EXCEPT
SELECT id_pedido, fecha, estado, forma_pago, total,
       id_usuario, nombre_usuario, apellido, mail
FROM   vista;

-- ============================================================
-- Vista 3 — v_tp5_detalle_pedido_productos
-- ============================================================

-- V3.1 — Filas de la vista que no están en la consulta manual
--       equivalente. Resultado esperado: 0 filas.
WITH vista AS (
    SELECT id_detalle, id_pedido, id_producto, nombre_producto,
           cantidad, precio_unitario, subtotal
    FROM   v_tp5_detalle_pedido_productos
    ORDER  BY id_pedido, id_detalle
),
manual AS (
    SELECT dp.id_detalle,
           dp.id_pedido,
           dp.id_producto,
           pr.nombre_producto,
           dp.cantidad,
           dp.precio_unitario,
           dp.subtotal
    FROM   detalle_pedido dp
    JOIN   producto       pr ON pr.id_producto = dp.id_producto
    WHERE  dp.eliminado = FALSE
    ORDER  BY dp.id_pedido, dp.id_detalle
)
SELECT id_detalle, id_pedido, id_producto, nombre_producto,
       cantidad, precio_unitario, subtotal
FROM   vista
EXCEPT
SELECT id_detalle, id_pedido, id_producto, nombre_producto,
       cantidad, precio_unitario, subtotal
FROM   manual;

-- V3.2 — Filas de la consulta manual equivalente que no están en
--       la vista. Resultado esperado: 0 filas.
WITH vista AS (
    SELECT id_detalle, id_pedido, id_producto, nombre_producto,
           cantidad, precio_unitario, subtotal
    FROM   v_tp5_detalle_pedido_productos
    ORDER  BY id_pedido, id_detalle
),
manual AS (
    SELECT dp.id_detalle,
           dp.id_pedido,
           dp.id_producto,
           pr.nombre_producto,
           dp.cantidad,
           dp.precio_unitario,
           dp.subtotal
    FROM   detalle_pedido dp
    JOIN   producto       pr ON pr.id_producto = dp.id_producto
    WHERE  dp.eliminado = FALSE
    ORDER  BY dp.id_pedido, dp.id_detalle
)
SELECT id_detalle, id_pedido, id_producto, nombre_producto,
       cantidad, precio_unitario, subtotal
FROM   manual
EXCEPT
SELECT id_detalle, id_pedido, id_producto, nombre_producto,
       cantidad, precio_unitario, subtotal
FROM   vista;

-- V3.3 — Control informativo de la regla de histórico: consulta
--       de control para los detalles de los productos id_producto
--       IN (4, 16). La vista solo filtra detalle_pedido.eliminado,
--       por lo que conserva detalles aunque el producto esté
--       eliminado lógicamente.
--       Interpretación del resultado (no es una verificación de
--       error de la vista):
--       - Si devuelve filas, demuestra que la vista conserva
--         detalles de productos eliminados.
--       - Si devuelve 0 filas, no es un error de la vista:
--         significa que la base no tiene detalles vigentes
--         asociados a productos eliminados.
SELECT id_detalle, id_pedido, id_producto, nombre_producto,
       cantidad, precio_unitario, subtotal
FROM   v_tp5_detalle_pedido_productos
WHERE  id_producto IN (4, 16)
ORDER  BY id_pedido, id_detalle;