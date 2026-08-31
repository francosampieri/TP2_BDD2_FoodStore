-- ============================================================
-- RESTRICCIONES DE INTEGRIDAD — TP2 FoodStore
-- Regla 1: Transiciones válidas de estado del pedido (pedido.estado)
-- Regla 2: Baja lógica de categorías con productos vigentes (categoria.eliminado)
--
-- Los triggers solo se disparan cuando la columna relevante cambia
-- de valor (WHEN ... IS DISTINCT FROM ...), por lo que no interfieren
-- con updates que tocan otras columnas ni con sp_crear_pedido (INSERT).
-- ============================================================

-- ============================================================
-- REGLA 1 — Transiciones válidas de estado del pedido
-- ============================================================

CREATE OR REPLACE FUNCTION fn_check_estado_transition()
RETURNS TRIGGER AS $$
BEGIN
    -- Permite conservar el mismo estado (sin cambio real)
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    -- TERMINADO y CANCELADO son estados finales: no pueden cambiar
    IF OLD.estado IN ('TERMINADO', 'CANCELADO') THEN
        RAISE EXCEPTION 'Estado final "%" no puede cambiar a "%"',
            OLD.estado, NEW.estado;
    END IF;

    -- Transiciones permitidas
    IF NOT (
        (OLD.estado = 'PENDIENTE'  AND NEW.estado IN ('CONFIRMADO', 'CANCELADO')) OR
        (OLD.estado = 'CONFIRMADO' AND NEW.estado IN ('TERMINADO',  'CANCELADO'))
    ) THEN
        RAISE EXCEPTION 'Transición de estado inválida: "%" -> "%"',
            OLD.estado, NEW.estado;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_estado_transition ON pedido;

CREATE TRIGGER trg_check_estado_transition
BEFORE UPDATE OF estado ON pedido
FOR EACH ROW
WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION fn_check_estado_transition();

-- ============================================================
-- REGLA 2 — Baja lógica de categorías con productos vigentes
-- ============================================================

CREATE OR REPLACE FUNCTION fn_check_categoria_baja_logica()
RETURNS TRIGGER AS $$
BEGIN
    -- Permite conservar el mismo valor de eliminado
    IF NEW.eliminado = OLD.eliminado THEN
        RETURN NEW;
    END IF;

    -- Solo se restringe la baja lógica (FALSE -> TRUE)
    IF NEW.eliminado = TRUE THEN
        IF EXISTS (
            SELECT 1
            FROM producto
            WHERE id_categoria = NEW.id_categoria
              AND eliminado = FALSE
        ) THEN
            RAISE EXCEPTION
                'No se puede eliminar la categoría %: tiene productos vigentes asociados',
                NEW.id_categoria;
        END IF;
    END IF;

    -- Reactivación (TRUE -> FALSE) siempre permitida
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_categoria_baja_logica ON categoria;

CREATE TRIGGER trg_check_categoria_baja_logica
BEFORE UPDATE OF eliminado ON categoria
FOR EACH ROW
WHEN (OLD.eliminado IS DISTINCT FROM NEW.eliminado)
EXECUTE FUNCTION fn_check_categoria_baja_logica();
