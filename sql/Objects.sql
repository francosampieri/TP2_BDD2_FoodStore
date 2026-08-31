-- 1. Vista de productos vigentes (activos, disponibles y con categoría activa)
CREATE VIEW v_productos_vigentes AS
SELECT p.id_producto,
       p.nombre_producto,
       p.precio,
       p.stock,
       p.descripcion_producto,
       p.imagen,
       p.disponible,
       c.id_categoria,
       c.nombre_categoria AS categoria
FROM   producto p
JOIN   categoria c ON c.id_categoria = p.id_categoria
WHERE  p.eliminado = FALSE 
  AND  c.eliminado = FALSE;

-- 2. Vista de resumen de pedidos
CREATE VIEW v_pedidos_resumen AS
SELECT ped.id_pedido,
       u.nombre_usuario || ' ' || u.apellido AS usuario,
       ped.fecha,
       ped.estado,
       ped.forma_pago,
       ped.total
FROM   pedido ped
JOIN   usuario u ON u.id_usuario = ped.id_usuario
WHERE  ped.eliminado = FALSE;

-- 3. Vista de detalle de pedidos
CREATE VIEW v_pedido_detalle AS
SELECT dp.id_detalle,
       dp.id_pedido,
       pr.nombre_producto AS producto,
       dp.cantidad,
       dp.precio_unitario,
       dp.subtotal
FROM   detalle_pedido dp
JOIN   producto pr ON pr.id_producto = dp.id_producto
WHERE  dp.eliminado = FALSE;

-- 4. Vista de categorías vigentes
CREATE VIEW v_categorias_vigentes AS
SELECT id_categoria,
       nombre_categoria,
       descripcion_categoria
FROM   categoria
WHERE  eliminado = FALSE;

CREATE OR REPLACE FUNCTION calcular_total_pedido(p_id_pedido BIGINT)
RETURNS NUMERIC(12,2) AS $$
    SELECT COALESCE(SUM(subtotal), 0.00)
    FROM   detalle_pedido
    WHERE  id_pedido = p_id_pedido 
      AND  eliminado = FALSE;
$$ LANGUAGE sql STABLE;

-- 1. Trigger BEFORE para autocompletar precio_unitario y calcular subtotal por fila
CREATE OR REPLACE FUNCTION fn_set_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    -- Si no se pasó precio_unitario, toma el precio actual del producto
    IF NEW.precio_unitario IS NULL THEN
        SELECT precio INTO NEW.precio_unitario
        FROM producto 
        WHERE id_producto = NEW.id_producto;
    END IF;
    
    NEW.subtotal := NEW.cantidad * NEW.precio_unitario;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_subtotal
BEFORE INSERT OR UPDATE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fn_set_subtotal();


-- 2. Función AFTER a nivel de sentencia para recalcular los pedidos afectados
CREATE OR REPLACE FUNCTION fn_recalcular_total()
RETURNS TRIGGER AS $$
BEGIN
    -- Recalcula el total de cada pedido afectado usando la tabla de transición
    UPDATE pedido p
    SET total = calcular_total_pedido(p.id_pedido)
    WHERE p.id_pedido IN (SELECT id_pedido FROM afectados);
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


-- 3. Triggers por evento con Transition Tables
CREATE TRIGGER trg_total_ins
AFTER INSERT ON detalle_pedido
REFERENCING NEW TABLE AS afectados
FOR EACH STATEMENT EXECUTE FUNCTION fn_recalcular_total();

CREATE TRIGGER trg_total_upd
AFTER UPDATE ON detalle_pedido
REFERENCING NEW TABLE AS afectados
FOR EACH STATEMENT EXECUTE FUNCTION fn_recalcular_total();


-- PROCEDIMIENTO: alta de pedido + detalles en una sola transacción

CREATE OR REPLACE PROCEDURE sp_crear_pedido(
    p_id_usuario BIGINT,
    p_forma_pago forma_pago,
    p_items      JSONB   -- [{"producto_id":1,"cantidad":2}, ...]
)
AS $$
DECLARE
    v_id_pedido   BIGINT;
    v_item        JSONB;
    v_id_producto BIGINT;
    v_cantidad    INTEGER;
    v_stock       INTEGER;
    v_disponible  BOOLEAN;
BEGIN
    -- El usuario debe existir y no estar eliminado
    IF NOT EXISTS (
        SELECT 1 FROM usuario
        WHERE id_usuario = p_id_usuario AND eliminado = FALSE
    ) THEN
        RAISE EXCEPTION 'Usuario % inexistente o eliminado', p_id_usuario;
    END IF;

    INSERT INTO pedido (id_usuario, forma_pago)
    VALUES (p_id_usuario, p_forma_pago)
    RETURNING id_pedido INTO v_id_pedido;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_id_producto := (v_item ->> 'producto_id')::BIGINT;
        v_cantidad    := (v_item ->> 'cantidad')::INTEGER;

        -- Bloquea la fila del producto para evitar sobreventa concurrente
        SELECT stock, disponible INTO v_stock, v_disponible
        FROM producto
        WHERE id_producto = v_id_producto AND eliminado = FALSE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto % inexistente o eliminado', v_id_producto;
        END IF;

        IF NOT v_disponible THEN
            RAISE EXCEPTION 'Producto % no disponible', v_id_producto;
        END IF;

        IF v_stock < v_cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente (producto %): hay %, se piden %',
                v_id_producto, v_stock, v_cantidad;
        END IF;

        INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad)
        VALUES (v_id_pedido, v_id_producto, v_cantidad);

        -- Descuenta stock dentro de la misma transacción
        UPDATE producto
        SET stock = stock - v_cantidad
        WHERE id_producto = v_id_producto;
    END LOOP;

    -- Si alguna validación falla (RAISE EXCEPTION), toda la transacción
    -- envolvente se revierte: no queda ni el pedido ni ningún detalle.
END;
$$ LANGUAGE plpgsql;