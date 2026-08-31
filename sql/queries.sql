-- Epica 1: Gestion de Categorias

-- HU-CAT-01: Listar categorias vigentes
SELECT id_categoria, nombre_categoria, descripcion_categoria
FROM categoria
WHERE eliminado = FALSE
ORDER BY id_categoria;

-- HU-CAT-02: Crear categoria
INSERT INTO categoria (nombre_categoria, descripcion_categoria)
VALUES ('Sushi', 'Variedad de sushi y rolls')
RETURNING id_categoria;

-- HU-CAT-03: Editar categoria
UPDATE categoria
SET nombre_categoria = 'Pizzas Artesanales',
    descripcion_categoria = 'Catalogo ampliado de pizzas'
WHERE id_categoria = 1 AND eliminado = FALSE;

-- HU-CAT-04: Eliminar categoria (baja logica)
-- Se da de baja la categoria creada en HU-CAT-02 (id_categoria = 8)
UPDATE categoria
SET eliminado = TRUE
WHERE id_categoria = 8 AND eliminado = FALSE;

-- Epica 2: Gestion de Productos

-- HU-PROD-01: Listar productos vigentes con su categoria
SELECT p.id_producto, p.nombre_producto, p.precio, p.stock, c.nombre_categoria AS categoria
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE p.eliminado = FALSE
ORDER BY p.id_producto;

-- HU-PROD-02: Crear producto (valida categoria existente y vigente)
INSERT INTO producto (nombre_producto, descripcion_producto, precio, stock, imagen, disponible, id_categoria)
SELECT 'Provoleta', 'Provoleta a la parrilla', 2200.00, 15, NULL, TRUE, c.id_categoria
FROM categoria c
WHERE c.id_categoria = 3 AND c.eliminado = false
RETURNING id_producto;

-- HU-PROD-03: Editar producto
UPDATE producto
SET precio = COALESCE(2400.00, precio),
    stock  = COALESCE(NULL, stock)
WHERE id_producto = 1 AND eliminado = FALSE;

-- HU-PROD-04: Eliminar producto (baja logica)
UPDATE producto
SET eliminado = TRUE
WHERE id_producto = 25 AND eliminado = FALSE;

-- Epica 3: Gestion de Usuarios

-- HU-USR-01: Listar usuarios vigentes
SELECT id_usuario, nombre_usuario, apellido, mail, rol
FROM usuario
WHERE eliminado = FALSE
ORDER BY id_usuario;

-- HU-USR-02: Crear usuario
INSERT INTO usuario (nombre_usuario, apellido, mail, celular, contrasena)
VALUES ('Marcos', 'Iturbe', 'marcos.iturbe@mail.com', '2618888888', '999')
RETURNING id_usuario;

-- HU-USR-03: Editar usuario
UPDATE usuario
SET celular = '2619999999'
WHERE id_usuario = 3 AND eliminado = FALSE;

-- HU-USR-04: Eliminar usuario (baja logica)
-- Se da de baja el usuario creado en HU-USR-02 (id_usuario = 9)
UPDATE usuario
SET eliminado = TRUE
WHERE id_usuario = 9 AND eliminado = FALSE;

-- Epica 4: Gestion de Pedidos y Detalles

-- HU-PED-01: Listar pedidos vigentes
SELECT id_pedido, usuario, fecha, estado, forma_pago, total
FROM v_pedidos_resumen
ORDER BY id_pedido;

-- HU-PED-02: Crear pedido con detalles (transaccional, via procedimiento)
CALL sp_crear_pedido(
    2,
    'EFECTIVO',
    '[{"producto_id":1,"cantidad":2},{"producto_id":13,"cantidad":1}]'::jsonb
);

-- HU-PED-03: Actualizar estado / forma de pago
UPDATE pedido
SET estado = 'CONFIRMADO', forma_pago = 'TARJETA'
WHERE id_pedido = 18 AND eliminado = FALSE;

-- HU-PED-04: Eliminar pedido (baja logica de pedido + sus detalles)
BEGIN;
UPDATE detalle_pedido SET eliminado = TRUE WHERE id_pedido = 14;
UPDATE pedido SET eliminado = TRUE WHERE id_pedido = 14;
COMMIT;

-- Consultas analiticas adicionales

-- A) Top 5 productos mas vendidos (por cantidad)
SELECT pr.id_producto, pr.nombre_producto, SUM(dp.cantidad) AS unidades
FROM detalle_pedido dp
JOIN producto pr ON pr.id_producto = dp.id_producto
WHERE dp.eliminado = FALSE
GROUP BY pr.id_producto, pr.nombre_producto
ORDER BY unidades DESC
LIMIT 5;

-- B) Facturacion por categoria y por mes
SELECT c.nombre_categoria AS categoria,
       date_trunc('month', ped.fecha) AS mes,
       SUM(dp.subtotal) AS facturado
FROM detalle_pedido dp
JOIN pedido ped ON ped.id_pedido = dp.id_pedido AND ped.eliminado = FALSE
JOIN producto pr ON pr.id_producto = dp.id_producto
JOIN categoria c ON c.id_categoria = pr.id_categoria
WHERE dp.eliminado = FALSE
GROUP BY c.nombre_categoria, date_trunc('month', ped.fecha)
ORDER BY mes, facturado DESC;

-- C) Ranking de usuarios por gasto acumulado (funcion de ventana)
SELECT u.id_usuario, u.nombre_usuario || ' ' || u.apellido AS usuario,
       SUM(ped.total) AS gasto,
       RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
FROM pedido ped
JOIN usuario u ON u.id_usuario = ped.id_usuario
WHERE ped.eliminado = FALSE
GROUP BY u.id_usuario, u.nombre_usuario, u.apellido
ORDER BY puesto;

-- D) Pedidos cuyo total supera el promedio general (subconsulta)
SELECT id_pedido, total
FROM pedido
WHERE eliminado = FALSE
  AND total > (SELECT AVG(total) FROM pedido WHERE eliminado = FALSE)
ORDER BY total DESC;

-- E) Productos sin ventas (LEFT JOIN + IS NULL)
SELECT pr.id_producto, pr.nombre_producto
FROM producto pr
LEFT JOIN detalle_pedido dp
       ON dp.id_producto = pr.id_producto AND dp.eliminado = FALSE
WHERE pr.eliminado = FALSE
  AND dp.id_detalle IS NULL
ORDER BY pr.id_producto;