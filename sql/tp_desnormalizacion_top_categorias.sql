-- ============================================================================
-- TP Unidad 4 — Parte 2: Desnormalización controlada — Top 5 diario de
--                          categorías por monto vendido
-- Base de ejecución: foodstore_tp_u4  (NUNCA en foodstore, foodstore_tp5, etc.)
-- Propósito: medir con EXPLAIN ANALYZE la consulta de 4 tablas, implementar
--            una vista materializada (1 fila por categoría del día) como
--            desnormalización controlada y auditar su equivalencia con EXCEPT.
-- ----------------------------------------------------------------------------
-- Correcciones aplicadas respecto de specs/tp_u4/plan_fnbc_desnormalizacion.md:
--   * Consulta adaptada a las columnas reales de schema.sql
--     (id_categoria/nombre_categoria, id_producto, id_pedido, subtotal, ...).
--   * La comprobación previa cuenta DETALLES vigentes de pedidos vigentes de
--     CURRENT_DATE (contar solo pedidos NO demuestra que haya ventas).
--   * Vista materializada SIN LIMIT en su definición + índice único
--     (id_categoria); el LIMIT 5 se aplica al consultar la vista.
--   * En este script NO aparece control_lote_almacen (es de la Parte 1).
--   * Los EXPLAIN ANALYZE (directa y vista) van en bloques separados para
--     ejecutar en DBeaver; no se reutilizan cifras de TP5.
--   * El BLOQUE 1b (caso de prueba opcional) está totalmente comentado y usa
--     CALL sp_crear_pedido (no INSERT directo en pedido/detalle_pedido).
--   * La auditoría EXCEPT (BLOQUES 5 y 6) se ejecuta justo después de poblar
--     la vista y ANTES de medir o modificar datos; la medición sobre la vista
--     (BLOQUE 7) va después y antepone EXPLAIN ANALYZE.
--   * Ejecutar por bloques (resaltar y ejecutar cada BLOQUE en DBeaver).
-- ============================================================================

-- >>> BLOQUE 1 — Comprobación previa de VENTAS del día <<<
-- Cuenta DETALLES vigentes de pedidos vigentes (fecha = CURRENT_DATE).
-- Copiar el número al informe.
-- Si devuelve 0, NO hay ventas de hoy: usar el BLOQUE 1b (todo comentado,
-- con CALL sp_crear_pedido) para crear el pedido de prueba; si devuelve >0,
-- copiar el valor y seguir con BLOQUE 2.
SELECT COUNT(*) AS detalles_vigentes_del_dia
FROM   detalle_pedido dp
JOIN   pedido         ped ON ped.id_pedido  = dp.id_pedido
                          AND ped.eliminado = FALSE
                          AND ped.fecha     = CURRENT_DATE
WHERE  dp.eliminado = FALSE;

-- >>> BLOQUE 1b — (OPCIONAL) Caso de prueba controlado — TODO COMENTADO <<<
-- Usar SOLO si el BLOQUE 1 devolvió 0. Ninguna sentencia es ejecutable
-- (todas están comentadas); para correrlas hay que descomentarlas a mano.
-- Para generar el pedido de prueba se usa CALL sp_crear_pedido(...), NO
-- INSERT directo en pedido/detalle_pedido: el procedimiento valida que el
-- usuario exista y no esté eliminado, que los productos existan y estén
-- disponibles, y que el stock alcance; luego descuenta el stock de forma
-- atómica (SELECT ... FOR UPDATE) y crea el pedido con fecha CURRENT_DATE
-- por DEFAULT (el total lo recalculan los triggers).
--
-- Antes de usarlo, COMPROBAR en DBeaver:
--   * que el usuario (id_usuario) existe y está vigente (eliminado = FALSE);
--   * que los productos existen, disponibles (disponible = TRUE) y no
--     eliminados;
--   * que el stock cubre las cantidades del pedido.
--
-- Ejemplo (usuario 1; productos 1 y 13 — verificar stock y disponibilidad):
--
-- CALL sp_crear_pedido(
--     1,
--     'EFECTIVO',
--     '[{"producto_id":1,"cantidad":1},{"producto_id":13,"cantidad":2}]'::jsonb
-- );
--
-- El procedimiento no devuelve el id del pedido: confirmarlo con
--     SELECT id_pedido, id_usuario, fecha, estado, total
--     FROM   pedido WHERE id_usuario = 1 ORDER BY id_pedido DESC LIMIT 1;
-- Registrar en el informe: id_pedido [ ___ ] y stock resultante.
-- Luego volver al BLOQUE 1 para confirmar detalles_vigentes_del_dia > 0.

-- >>> BLOQUE 2 — MEDICIÓN 1: consulta directa (ANTES de la vista) <<<
-- Ejecutar con EXPLAIN ANALYZE (no solo EXPLAIN). Copiar al informe:
--   * "Execution Time" en ms
--   * nodo que domina el costo (con su cost)
-- Esta es la línea base de este TP; NO usar cifras de TP5.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.id_categoria,
    c.nombre_categoria,
    SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido         ped ON ped.id_pedido  = dp.id_pedido
                          AND ped.eliminado = FALSE
                          AND ped.fecha     = CURRENT_DATE
JOIN   producto       pr  ON pr.id_producto = dp.id_producto
JOIN   categoria      c   ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria
ORDER  BY monto_vendido DESC
LIMIT  5;

-- >>> BLOQUE 3 — Vista materializada (desnormalización controlada) <<<
-- Una fila por categoría con ventas en el día. SIN LIMIT ni ORDER BY en la
-- definición de forma deliberada (el reporte aplica el top 5 al consultar).
-- NOTA: CURRENT_DATE se evalúa en el momento del REFRESH (foto instantánea),
-- no en el momento de la lectura — ver informe.
-- Resultado: "SELECT 1" ... ; confirmar filas con el BLOQUE 4.
CREATE MATERIALIZED VIEW mv_tp_u4_top5_cat_dia AS
SELECT
    c.id_categoria,
    c.nombre_categoria,
    SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido         ped ON ped.id_pedido  = dp.id_pedido
                          AND ped.eliminado = FALSE
                          AND ped.fecha     = CURRENT_DATE
JOIN   producto       pr  ON pr.id_producto = dp.id_producto
JOIN   categoria      c   ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria
WITH DATA;

-- >>> BLOQUE 4 — Índice único sobre la vista (para REFRESH CONCURRENTLY) <<<
-- La agrupación produce exactamente una fila por categoría, por eso
-- (id_categoria) es clave única. Copiar el conteo al informe.
CREATE UNIQUE INDEX uq_mv_tp_u4_top5_cat_dia
    ON mv_tp_u4_top5_cat_dia (id_categoria);

SELECT COUNT(*) AS filas_materializadas
FROM   mv_tp_u4_top5_cat_dia;

-- >>> BLOQUE 5 — Auditoría EXCEPT dirección A <<<
-- Se ejecuta inmediatamente después de crear y poblar la vista (BLOQUES 3 y 4)
-- y ANTES de medir o insertar datos nuevos: verifica que la vista materialice
-- exactamente lo mismo que la agregación directa sin LIMIT.
-- Filas de la agregación DIRECTA ausentes en la VISTA. Esperado: 0 FILAS.
-- Copiar el resultado al informe.
SELECT c.id_categoria, c.nombre_categoria, SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido ped ON ped.id_pedido  = dp.id_pedido
                 AND ped.eliminado = FALSE
                 AND ped.fecha     = CURRENT_DATE
JOIN   producto pr ON pr.id_producto = dp.id_producto
JOIN   categoria c ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria

EXCEPT

SELECT id_categoria, nombre_categoria, monto_vendido
FROM   mv_tp_u4_top5_cat_dia;

-- >>> BLOQUE 6 — Auditoría EXCEPT dirección B <<<
-- Filas de la VISTA ausentes en la agregación directa (sin LIMIT).
-- Esperado: 0 FILAS. Copiar el resultado al informe.
SELECT id_categoria, nombre_categoria, monto_vendido
FROM   mv_tp_u4_top5_cat_dia

EXCEPT

SELECT c.id_categoria, c.nombre_categoria, SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido ped ON ped.id_pedido  = dp.id_pedido
                 AND ped.eliminado = FALSE
                 AND ped.fecha     = CURRENT_DATE
JOIN   producto pr ON pr.id_producto = dp.id_producto
JOIN   categoria c ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria;

-- >>> BLOQUE 7 — MEDICIÓN 2: lectura sobre la vista (DESPUÉS) <<<
-- Ejecutar con EXPLAIN ANALYZE (no solo EXPLAIN): produce Execution Time y
-- plan real en DBeaver. Copiar al informe:
--   * "Execution Time" en ms
--   * tipo de nodo (esperado: Seq Scan sobre la tabla materializada, sin
--     joins y sin recorrer detalle_pedido)
EXPLAIN ANALYZE
SELECT id_categoria, nombre_categoria, monto_vendido
FROM   mv_tp_u4_top5_cat_dia
ORDER  BY monto_vendido DESC
LIMIT  5;

-- >>> BLOQUE 8 — REFRESH CONCURRENTLY (comentado, para usar más adelante) <<<
-- Primer populate: ya se hizo con WITH DATA (BLOQUE 3).
-- Refrescos posteriores, con el índice único ya creado:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tp_u4_top5_cat_dia;
-- CUÁNDO USARLO: para no bloquear lecturas del panel. La FECHA DETERMINA EL
-- CONTENIDO: un REFRESH de ayer materializa datos de ayer; la frecuencia
-- (ej.: cada hora durante horario operativo, o antes de abrir el panel) debe
-- acordarse con el negocio y documentarse en el informe.
-- ADVERTENCIA: la vista puede quedar desactualizada entre refrescos; no usar
-- para operaciones transaccionales ni para totales de pedidos activos.

-- >>> CIERRE — Qué copiar al informe y completar <<<
-- 1) BLOQUE 1: detalles_vigentes_del_dia (número real).
-- 2) BLOQUE 2 (MEDICIÓN 1): Execution Time de la consulta directa + nodo.
-- 3) BLOQUE 4: filas_materializadas (>= 1).
-- 4) BLOQUES 5 y 6: 0 filas cada uno (vista == agregación directa).
-- 5) BLOQUE 7 (MEDICIÓN 2): Execution Time de la vista + nodo dominante.
-- 6) Completar en docs/tp_u4/informe_tp_u4.md la tabla antes/después con los
--    tiempos reales, SIN reutilizar cifras de TP5.
-- ============================================================================