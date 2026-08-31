-- Escenario 1: Atomicidad de sp_crear_pedido
-- Una sola sesion.

SELECT count(*) AS pedidos_antes FROM pedido;
SELECT count(*) AS detalles_antes FROM detalle_pedido;

-- Caso 1a: se pide un producto que no existe
CALL sp_crear_pedido(2, 'EFECTIVO', '[{"producto_id":9999,"cantidad":1}]'::jsonb);
-- Da error: "Producto 9999 inexistente o eliminado"

-- Caso 1b: se pide cantidad 0
CALL sp_crear_pedido(3, 'TARJETA', '[{"producto_id":13,"cantidad":0}]'::jsonb);
-- Da error por el CHECK (cantidad > 0) de la tabla detalle_pedido

-- Los conteos de despues deben ser iguales a los de antes:
-- ningun pedido ni detalle quedo guardado.
SELECT count(*) AS pedidos_despues FROM pedido;
SELECT count(*) AS detalles_despues FROM detalle_pedido;

-- Escenario 2: Transaccion manual, COMMIT vs ROLLBACK
-- Una sola sesion.

SELECT stock FROM producto WHERE id_producto = 10;

BEGIN;
UPDATE producto SET stock = stock - 5 WHERE id_producto = 10;
COMMIT;

SELECT stock FROM producto WHERE id_producto = 10;
-- El stock quedo actualizado para siempre.

BEGIN;
UPDATE producto SET stock = stock - 5 WHERE id_producto = 10;
ROLLBACK;

SELECT stock FROM producto WHERE id_producto = 10;
-- El stock no cambio: el ROLLBACK deshizo el UPDATE anterior.


-- Escenario 3: Aislamiento - lectura no repetible
-- Requiere DOS terminales psql abiertas al mismo tiempo.

-- Preparacion
UPDATE producto SET stock = 20 WHERE id_producto = 11;

-- Prueba con READ COMMITTED (el nivel por defecto)

-- TERMINAL A
BEGIN;
SELECT stock FROM producto WHERE id_producto = 11;

-- TERMINAL B (mientras A sigue con la transaccion abierta)
UPDATE producto SET stock = stock - 5 WHERE id_producto = 11;

-- TERMINAL A (sin haber cerrado la transaccion todavia)
SELECT stock FROM producto WHERE id_producto = 11;
-- ahora deberia mostrar 15
COMMIT;

-- Prueba con SERIALIZABLE, mismo experimento

UPDATE producto SET stock = 20 WHERE id_producto = 11;

-- TERMINAL A
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT stock FROM producto WHERE id_producto = 11;
-- deberia mostrar 20

-- TERMINAL B
UPDATE producto SET stock = stock - 5 WHERE id_producto = 11;

-- TERMINAL A (sin cerrar la transaccion)
SELECT stock FROM producto WHERE id_producto = 11;
-- esta vez sigue mostrando 20
COMMIT;

SELECT stock FROM producto WHERE id_producto = 11;
-- recien aca, sin transaccion abierta, se ve el 15 que dejo B

-- Escenario 4: SELECT ... FOR UPDATE evita la sobreventa
-- Requiere DOS terminales psql abiertas al mismo tiempo.

-- Version sin control, para ver el problema

UPDATE producto SET stock = 1 WHERE id_producto = 11; -- ultima unidad

-- Crear dos pedidos vacios, uno para cada terminal, y anotar los ids
INSERT INTO pedido (forma_pago, id_usuario) VALUES ('EFECTIVO', 2) RETURNING id_pedido;
INSERT INTO pedido (forma_pago, id_usuario) VALUES ('TARJETA', 3) RETURNING id_pedido;

-- TERMINAL A (cambiar 28 por el id_pedido anotado para A)
BEGIN;
SELECT stock FROM producto WHERE id_producto = 11;
-- muestra 1
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad) VALUES (28, 11, 1);
UPDATE producto SET stock = 0 WHERE id_producto = 11;
COMMIT;

-- TERMINAL B (cambiar 29 por el id_pedido anotado para B), ejecutar
-- mientras A todavia no hizo COMMIT
BEGIN;
SELECT stock FROM producto WHERE id_producto = 11;
-- tambien muestra 1
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad) VALUES (29, 11, 1);
UPDATE producto SET stock = 0 WHERE id_producto = 11;
COMMIT;

-- Verificacion: quedaron dos ventas para un producto con una sola
-- unidad de stock.
SELECT stock FROM producto WHERE id_producto = 11;
SELECT id_pedido, cantidad FROM detalle_pedido WHERE id_producto = 11 ORDER BY id_pedido DESC LIMIT 2;

-- Version con control, usando sp_crear_pedido

UPDATE producto SET stock = 1 WHERE id_producto = 11;

-- TERMINAL A
BEGIN;
CALL sp_crear_pedido(2, 'EFECTIVO', '[{"producto_id":11,"cantidad":1}]'::jsonb);
-- Acciones de terminal B
COMMIT;

-- TERMINAL B
CALL sp_crear_pedido(3, 'TARJETA', '[{"producto_id":11,"cantidad":1}]'::jsonb);
-- Se queda esperando hasta que cierre la transaccion A, y despues
-- responde con error de stock insuficiente en vez de vender de mas

SELECT stock FROM producto WHERE id_producto = 11;
SELECT id_pedido, cantidad FROM detalle_pedido WHERE id_producto = 11 ORDER BY id_pedido DESC LIMIT 3;
