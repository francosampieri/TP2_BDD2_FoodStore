-- ============================================================
-- PRUEBAS DE RESTRICCIONES DE INTEGRIDAD — TP2 FoodStore
--
-- IMPORTANTE:
--  * Ejecutar únicamente sobre foodstore_tp2.
--  * Cada caso se ejecuta dentro de su PROPIO bloque BEGIN / ROLLBACK,
--    porque RAISE EXCEPTION aborta la transacción activa.
--  * Cuando se produce una excepción esperada, DBeaver puede
--    cortar la ejecución del script. En ese caso el ROLLBACK debe
--    ejecutarse manualmente en la MISMA conexión/sesión de DBeaver
--    (no en una pestaña/sesión nueva), en una sentencia separada.
-- ============================================================

-- ============================================================
-- REGLA 1 — Transiciones válidas de estado del pedido
-- ============================================================
-- ids usados (del seed data):
--   pedido 15 = PENDIENTE
--   pedido 17 = CONFIRMADO
--   pedido 2  = TERMINADO
--   pedido 6  = CANCELADO

-- CASO 1 (VÁLIDO): PENDIENTE -> CONFIRMADO
BEGIN;
UPDATE pedido SET estado = 'CONFIRMADO' WHERE id_pedido = 15 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 15;
ROLLBACK;

-- CASO 2 (VÁLIDO): PENDIENTE -> CANCELADO
BEGIN;
UPDATE pedido SET estado = 'CANCELADO' WHERE id_pedido = 15 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 15;
ROLLBACK;

-- CASO 3 (VÁLIDO): CONFIRMADO -> TERMINADO
BEGIN;
UPDATE pedido SET estado = 'TERMINADO' WHERE id_pedido = 17 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 17;
ROLLBACK;

-- CASO 4 (VÁLIDO): CONFIRMADO -> CANCELADO
BEGIN;
UPDATE pedido SET estado = 'CANCELADO' WHERE id_pedido = 17 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 17;
ROLLBACK;

-- CASO 5 (INVÁLIDO): PENDIENTE -> TERMINADO
-- Excepción esperada. Si DBeaver corta la ejecución, ejecutar
-- ROLLBACK manualmente en la MISMA conexión.
BEGIN;
UPDATE pedido SET estado = 'TERMINADO' WHERE id_pedido = 15 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 15;
ROLLBACK;

-- CASO 6 (INVÁLIDO): CONFIRMADO -> PENDIENTE
-- Excepción esperada.
BEGIN;
UPDATE pedido SET estado = 'PENDIENTE' WHERE id_pedido = 17 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 17;
ROLLBACK;

-- CASO 7 (INVÁLIDO): TERMINADO -> CONFIRMADO
-- Excepción esperada (estado final).
BEGIN;
UPDATE pedido SET estado = 'CONFIRMADO' WHERE id_pedido = 2 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 2;
ROLLBACK;

-- CASO 8 (INVÁLIDO): CANCELADO -> PENDIENTE
-- Excepción esperada (estado final).
BEGIN;
UPDATE pedido SET estado = 'PENDIENTE' WHERE id_pedido = 6 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 6;
ROLLBACK;

-- CASO 9 (VÁLIDO): mismo estado, sin cambio real
BEGIN;
UPDATE pedido SET estado = estado WHERE id_pedido = 15 AND eliminado = FALSE;
SELECT id_pedido, estado FROM pedido WHERE id_pedido = 15;
ROLLBACK;

-- CASO 10 (VÁLIDO): actualizar otra columna sin tocar estado.
-- El trigger no se dispara (WHEN estado IS DISTINCT FROM estado = FALSE).
BEGIN;
UPDATE pedido SET forma_pago = 'TARJETA' WHERE id_pedido = 17 AND eliminado = FALSE;
SELECT id_pedido, estado, forma_pago FROM pedido WHERE id_pedido = 17;
ROLLBACK;

-- ============================================================
-- REGLA 2 — Baja lógica de categorías con productos vigentes
-- ============================================================

-- CASO 1 (VÁLIDO): dar de baja una categoría sin productos vigentes.
-- No depende de datos existentes: se inserta una categoría temporal
-- con nombre único, se marca como eliminada y se comprueba con RETURNING.
-- Todo queda revertido con ROLLBACK.
BEGIN;
INSERT INTO categoria (nombre_categoria, descripcion_categoria)
VALUES ('Temp Sin Productos', 'Categoria temporal sin productos vigentes')
RETURNING id_categoria;

UPDATE categoria
SET eliminado = TRUE
WHERE nombre_categoria = 'Temp Sin Productos'
RETURNING id_categoria, eliminado;
ROLLBACK;

-- CASO 2 (INVÁLIDO): dar de baja una categoría con productos vigentes.
-- Excepción esperada. Si DBeaver corta la ejecución, ejecutar
-- ROLLBACK manualmente en la MISMA conexión.
BEGIN;
UPDATE categoria SET eliminado = TRUE WHERE id_categoria = 1; -- tiene productos activos
SELECT id_categoria, eliminado FROM categoria WHERE id_categoria = 1;
ROLLBACK;

-- CASO 3 (VÁLIDO): reactivar una categoría eliminada (TRUE -> FALSE).
BEGIN;
UPDATE categoria SET eliminado = FALSE WHERE id_categoria = 7; -- 'Ensaladas' (eliminada en data.sql)
SELECT id_categoria, eliminado FROM categoria WHERE id_categoria = 7;
ROLLBACK;

-- CASO 4 (VÁLIDO): dar de baja una categoría donde todos sus
-- productos están eliminados. No depende de datos existentes: se
-- insertan categoría y producto temporales, se elimina el producto,
-- y se da de baja la categoría comprobándolo con RETURNING.
-- Todo queda revertido con ROLLBACK.
BEGIN;
INSERT INTO categoria (nombre_categoria, descripcion_categoria)
VALUES ('Temp Prod Eliminado', 'Categoria temporal con producto eliminado')
RETURNING id_categoria;

INSERT INTO producto (nombre_producto, precio, stock, id_categoria, disponible)
SELECT 'Prod Temporal', 100.00, 1, id_categoria, TRUE
FROM categoria
WHERE nombre_categoria = 'Temp Prod Eliminado';

UPDATE producto
SET eliminado = TRUE
WHERE nombre_producto = 'Prod Temporal'
  AND id_categoria = (SELECT id_categoria FROM categoria WHERE nombre_categoria = 'Temp Prod Eliminado')
RETURNING id_producto, eliminado;

UPDATE categoria
SET eliminado = TRUE
WHERE nombre_categoria = 'Temp Prod Eliminado'
RETURNING id_categoria, eliminado;
ROLLBACK;
