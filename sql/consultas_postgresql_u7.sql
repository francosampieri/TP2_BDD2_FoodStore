-- TP7 FoodStore: ejecutar sobre foodstore en DBeaver.
-- Las consultas se restringen a los mismos cinco pedidos migrados a MongoDB.
-- _id de MongoDB corresponde a pedido.id_pedido.
-- No se filtra producto.eliminado: las lineas conservan su valor historico.

SELECT current_database() AS base_origen;

-- b) Estado TERMINADO. Esperado en la muestra: 2, 3, 12.
SELECT p.id_pedido, p.estado
FROM pedido AS p
JOIN usuario AS u ON u.id_usuario = p.id_usuario
WHERE p.id_pedido IN (2, 3, 6, 11, 12)
  AND p.eliminado = FALSE
  AND u.eliminado = FALSE
  AND p.estado = 'TERMINADO'
ORDER BY p.id_pedido;

-- c) Producto 9 en una linea vigente. Esperado en la muestra: 3, 12.
SELECT DISTINCT p.id_pedido
FROM pedido AS p
JOIN usuario AS u ON u.id_usuario = p.id_usuario
JOIN detalle_pedido AS dp ON dp.id_pedido = p.id_pedido
WHERE p.id_pedido IN (2, 3, 6, 11, 12)
  AND p.eliminado = FALSE
  AND u.eliminado = FALSE
  AND dp.eliminado = FALSE
  AND dp.id_producto = 9
ORDER BY p.id_pedido;
