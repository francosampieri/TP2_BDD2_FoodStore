-- ============================================================
-- VISTAS TP5 — FoodStore (Parte B)
--
-- Base de ejecución documentada: foodstore_tp3 / foodstore_tp5
-- (PostgreSQL 17).
-- Tres vistas nuevas especificadas en specs/vistas_tp5.md.
-- Las vistas existentes de Objects.sql (v_productos_vigentes,
-- v_pedidos_resumen, v_pedido_detalle, v_categorias_vigentes) no
-- se modifican ni reemplazan: las de TP5 son complementarias.
--
-- Sin DROP VIEW y sin CREATE OR REPLACE: solo CREATE VIEW nuevo.
-- ============================================================

-- ============================================================
-- Vista 1 — v_tp5_productos_categoria
-- ============================================================
-- Catálogo completo para reportes: producto vigente con su
-- categoría desnormalizada (precio, stock, disponibilidad).
-- INNER JOIN con categoria (FK id_categoria NOT NULL); si la
-- categoría está eliminada, el producto se excluye.
-- Filtros independientes: producto.eliminado = FALSE y
-- categoria.eliminado = FALSE.

CREATE VIEW v_tp5_productos_categoria AS
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
  AND  c.eliminado = FALSE;

-- ============================================================
-- Vista 2 — v_tp5_pedidos_usuario
-- ============================================================
-- Pedidos con identidad completa del usuario en columnas
-- separadas (reporte administrativo y auditoría). INNER JOIN con
-- usuario (FK id_usuario NOT NULL); si el usuario está eliminado,
-- el pedido se excluye de reportes activos.
-- Filtros independientes: pedido.eliminado = FALSE y
-- usuario.eliminado = FALSE.
-- Seguridad: NO expone contrasena, celular ni rol; mail queda
-- incluido como contacto administrativo según la especificación.

CREATE VIEW v_tp5_pedidos_usuario AS
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
  AND  u.eliminado   = FALSE;

-- ============================================================
-- Vista 3 — v_tp5_detalle_pedido_productos
-- ============================================================
-- Detalle de líneas de pedido con nombre del producto para
-- reportes de ventas e historial. Regla central: preservar los
-- detalles históricos aunque el producto haya sido eliminado
-- lógicamente.
-- INNER JOIN con producto (FK id_producto NOT NULL) PERO sin
-- filtrar producto.eliminado: el nombre se toma como fuente de
-- descripción; la vigencia del producto NO condiciona la vigencia
-- del detalle.
-- Único filtro de vigencia: detalle_pedido.eliminado = FALSE.

CREATE VIEW v_tp5_detalle_pedido_productos AS
SELECT dp.id_detalle,
       dp.id_pedido,
       dp.id_producto,
       pr.nombre_producto,
       dp.cantidad,
       dp.precio_unitario,
       dp.subtotal
FROM   detalle_pedido dp
JOIN   producto       pr ON pr.id_producto = dp.id_producto
WHERE  dp.eliminado = FALSE;