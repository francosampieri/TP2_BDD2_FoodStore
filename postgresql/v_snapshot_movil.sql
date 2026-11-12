-- postgresql/v_snapshot_movil.sql
-- Vista de instantánea para la tablet (ejecutar en PostgreSQL de PRUEBAS, ej. foodstore_u8)
-- Adaptada al esquema real: producto (id_producto, nombre_producto, precio, stock, disponible, eliminado, id_categoria)
-- y categoria (id_categoria, eliminado). La tabla real es usuario (no cliente) pero no se expone.

CREATE OR REPLACE VIEW v_snapshot_movil AS
SELECT
    p.id_producto                              AS producto_id,
    p.nombre_producto                          AS nombre,
    CAST(ROUND(p.precio * 100) AS INTEGER)     AS precio_centavos,
    p.stock                                    AS stock,
    p.disponible                               AS disponible,
    (p.eliminado OR c.eliminado)               AS eliminado,
    now()                                      AS capturado_en
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria;
-- Sin WHERE: las bajas (producto o categoría) viajan como lápidas.
-- No se exponen columnas de usuario ni datos personales.
