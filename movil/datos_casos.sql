-- datos_casos.sql
-- Datos de prueba para casos C2-C6 (TP8).
-- Ejecutar en SQLite DESPUÉS de:
--   1) movil/schema_sqlite.sql
--   2) Vaciar snapshot_servidor, importar CSV real de foodstore_u8 y ejecutar movil/cargar_snapshot.sql
--      (producto_cache debe contener la instantánea real).
--
-- NO crea productos inventados (101-105). Usa productos reales de producto_cache.
-- Los cambios de precio/stock/baja en PostgreSQL (C2-C4) se hacen manualmente en la copia
-- de PRUEBAS antes de exportar una NUEVA instantánea; al reimportar, cargar_snapshot.sql hace
-- UPSERT sobre producto_cache, por lo que conserva las filas referenciadas por item_borrador
-- (FK sin ON DELETE CASCADE) y C4 puede recibir la lápida sin perder el ítem.
--
-- SIMULADO_APROBADO solo actualiza SQLite; no modifica PostgreSQL ni llama sp_crear_pedido.

PRAGMA foreign_keys = ON;

-- ============================================================
-- CONSULTA PREVIA: candidatos reales de la instantánea importada
-- Revisar ID, nombre, precio, stock y vigencia antes de usar los casos.
-- ============================================================
SELECT producto_id, nombre, precio_centavos, stock_visto, disponible_visto, eliminado, capturado_en
FROM producto_cache
ORDER BY producto_id;

-- Selección de 5 productos vigentes distintos para C2-C6 (ordenados por producto_id).
-- Si hay menos de 5 vigentes, se usarán los disponibles y algunos casos pueden no insertarse.
DROP TABLE IF EXISTS temp._candidatos;
CREATE TEMP TABLE _candidatos AS
WITH vigentes AS (
    SELECT
        producto_id,
        nombre,
        precio_centavos,
        stock_visto,
        disponible_visto,
        eliminado,
        ROW_NUMBER() OVER (ORDER BY producto_id) AS rn
    FROM producto_cache
    WHERE eliminado = 0
      AND disponible_visto = 1
)
SELECT * FROM vigentes WHERE rn <= 5;

SELECT 'candidato' AS tipo, rn, producto_id, nombre, precio_centavos, stock_visto, disponible_visto, eliminado
FROM temp._candidatos
ORDER BY rn;

-- Mapeo explícito por caso (para referencia en los pasos manuales C2-C4)
DROP TABLE IF EXISTS temp._casos;
CREATE TEMP TABLE _casos (caso TEXT PRIMARY KEY, producto_id INTEGER, precio_centavos INTEGER, stock_visto INTEGER);
INSERT INTO temp._casos (caso, producto_id, precio_centavos, stock_visto)
SELECT 'C2', producto_id, precio_centavos, stock_visto FROM temp._candidatos WHERE rn = 1;
INSERT INTO temp._casos (caso, producto_id, precio_centavos, stock_visto)
SELECT 'C3', producto_id, precio_centavos, stock_visto FROM temp._candidatos WHERE rn = 2;
INSERT INTO temp._casos (caso, producto_id, precio_centavos, stock_visto)
SELECT 'C4', producto_id, precio_centavos, stock_visto FROM temp._candidatos WHERE rn = 3;
INSERT INTO temp._casos (caso, producto_id, precio_centavos, stock_visto)
SELECT 'C5', producto_id, precio_centavos, stock_visto FROM temp._candidatos WHERE rn = 4;
INSERT INTO temp._casos (caso, producto_id, precio_centavos, stock_visto)
SELECT 'C6', producto_id, precio_centavos, stock_visto FROM temp._candidatos WHERE rn = 5;

SELECT caso, producto_id, precio_centavos AS precio_visto_centavos, stock_visto
FROM temp._casos
ORDER BY caso;

-- ============================================================
-- C2: conflicto por precio (luego reenvío tras aceptar nuevo precio)
-- Usa producto real: precio_visto tomado de producto_cache.
-- ============================================================
INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
SELECT 'c2000000-0000-4000-8000-000000000002', 2, 'EFECTIVO'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C2');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'c2000000-0000-4000-8000-000000000002', producto_id, 1, precio_centavos
FROM temp._casos WHERE caso = 'C2';

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
SELECT 'c2000000-0000-4000-8000-100000000002', 'c2000000-0000-4000-8000-000000000002', 'PENDIENTE'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C2');

-- FLUJO C2 (manual; reemplazar <ID_C2> por el producto_id del caso C2 mostrado arriba):
-- 1) En PostgreSQL de PRUEBAS (foodstore_u8), cambiar el precio de <ID_C2> y exportar nueva
--    instantánea. En SQLite: vaciar snapshot_servidor, importar CSV, ejecutar cargar_snapshot.sql.
--    (El UPSERT conserva producto_cache/item_borrador.)
--    Correr movil/semaforo.sql: la solicitud c200...1000...0002 quedará en CONFLICTO.
-- 2) El cliente acepta el nuevo precio (leerlo de producto_cache tras recargar):
--      -- Consultar nuevo precio:
--      SELECT producto_id, precio_centavos FROM producto_cache WHERE producto_id = <ID_C2>;
--      -- Actualizar ítem con el precio aceptado:
--      UPDATE item_borrador
--         SET precio_centavos_visto = (SELECT precio_centavos FROM producto_cache WHERE producto_id = <ID_C2>)
--       WHERE id_local = 'c2000000-0000-4000-8000-000000000002'
--         AND producto_id = <ID_C2>;
-- 3) Crear una NUEVA solicitud PENDIENTE para el mismo borrador (la anterior sigue CONFLICTO;
--    el índice parcial ux_cola_una_pendiente lo permite):
--      INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
--      VALUES ('c2000000-0000-4000-8000-200000000002',
--              'c2000000-0000-4000-8000-000000000002',
--              'PENDIENTE');
-- 4) Correr movil/semaforo.sql nuevamente: la nueva solicitud dará SIMULADO_APROBADO.

-- ============================================================
-- C3: rechazado por stock insuficiente (cantidad = stock_visto + 1)
-- Usa producto real y stock_visto actual de producto_cache (sin inventar valores).
-- ============================================================
INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
SELECT 'c3000000-0000-4000-8000-000000000003', 2, 'EFECTIVO'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C3');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'c3000000-0000-4000-8000-000000000003', producto_id, stock_visto + 1, precio_centavos
FROM temp._casos WHERE caso = 'C3';

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
SELECT 'c3000000-0000-4000-8000-100000000003', 'c3000000-0000-4000-8000-000000000003', 'PENDIENTE'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C3');

-- ============================================================
-- C4: rechazado por baja lógica
-- Usa producto real. La baja se aplica en PostgreSQL de PRUEBAS antes de reexportar.
-- Al recargar la lápida (eliminado/disponible cambiados), cargar_snapshot.sql hace UPSERT
-- y conserva la fila en producto_cache, por lo que el ítem de item_borrador (FK) se mantiene.
-- ============================================================
INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
SELECT 'c4000000-0000-4000-8000-000000000004', 2, 'EFECTIVO'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C4');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'c4000000-0000-4000-8000-000000000004', producto_id, 1, precio_centavos
FROM temp._casos WHERE caso = 'C4';

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
SELECT 'c4000000-0000-4000-8000-100000000004', 'c4000000-0000-4000-8000-000000000004', 'PENDIENTE'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C4');

-- FLUJO C4 (manual; reemplazar <ID_C4> por el producto_id del caso C4):
-- 1) En PostgreSQL de PRUEBAS, marcar baja lógica de <ID_C4> (producto o categoría) y exportar snapshot.
-- 2) En SQLite: vaciar snapshot_servidor, importar CSV, ejecutar cargar_snapshot.sql.
--    Verificar que el ítem se conserva (FK intacta) y que producto_cache refleja la lápida,
--    y que v_catalogo_disponible oculta el producto mientras item_borrador conserva la referencia:
--      SELECT * FROM producto_cache WHERE producto_id = <ID_C4>;
--      SELECT * FROM item_borrador WHERE id_local = 'c4000000-0000-4000-8000-000000000004';
--      -- La lápida debe ocultarlo del catálogo visible (sin filas para <ID_C4>):
--      SELECT * FROM v_catalogo_disponible WHERE producto_id = <ID_C4>;
-- 3) Correr movil/semaforo.sql: la solicitud quedará RECHAZADO por baja.

-- ============================================================
-- C5: SIMULADO_APROBADO (sin cambios en el servidor entre snapshot y semáforo)
-- Usa producto real y precio_visto de producto_cache (coincidirá con snapshot).
-- ============================================================
INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
SELECT 'c5000000-0000-4000-8000-000000000005', 2, 'EFECTIVO'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C5');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'c5000000-0000-4000-8000-000000000005', producto_id, 1, precio_centavos
FROM temp._casos WHERE caso = 'C5';

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
SELECT 'c5000000-0000-4000-8000-100000000005', 'c5000000-0000-4000-8000-000000000005', 'PENDIENTE'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C5');

-- ============================================================
-- C6: idempotencia (misma solicitud_uuid no se duplica)
-- Usa producto real y precio_visto de producto_cache.
-- ============================================================
INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
SELECT 'c6000000-0000-4000-8000-000000000006', 2, 'EFECTIVO'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C6');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'c6000000-0000-4000-8000-000000000006', producto_id, 1, precio_centavos
FROM temp._casos WHERE caso = 'C6';

-- Solicitud inicial (se crea una sola vez)
INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
SELECT 'c6000000-0000-4000-8000-100000000006', 'c6000000-0000-4000-8000-000000000006', 'PENDIENTE'
WHERE EXISTS (SELECT 1 FROM temp._casos WHERE caso = 'C6');

-- Estado actual y cantidad de filas (ejecución normal del script)
SELECT solicitud_uuid, id_local, estado, motivo,
       COUNT(*) OVER () AS cantidad_filas
FROM cola_sync
WHERE solicitud_uuid = 'c6000000-0000-4000-8000-100000000006';

-- Intento duplicado (MISMO solicitud_uuid) - DEBE FALLAR por PRIMARY KEY.
-- Ejecutar de forma AISLADA para observar el error sin interrumpir el resto.
--   INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
--   VALUES ('c6000000-0000-4000-8000-100000000006', 'c6000000-0000-4000-8000-000000000006', 'PENDIENTE');
--
-- Inmediatamente después de ese intento (fallido), ejecutar esta verificación:
--   SELECT solicitud_uuid, id_local, estado, motivo, COUNT(*) AS cantidad_filas
--   FROM cola_sync
--   WHERE solicitud_uuid = 'c6000000-0000-4000-8000-100000000006'
--   GROUP BY solicitud_uuid, id_local, estado, motivo;
--   -- Debe mostrar la misma fila y cantidad_filas = 1.

-- Resumen de casos preparados
SELECT c.solicitud_uuid, c.id_local, c.estado, c.motivo
FROM cola_sync c
WHERE c.id_local IN (
    'c2000000-0000-4000-8000-000000000002',
    'c3000000-0000-4000-8000-000000000003',
    'c4000000-0000-4000-8000-000000000004',
    'c5000000-0000-4000-8000-000000000005',
    'c6000000-0000-4000-8000-000000000006'
)
ORDER BY c.id_local, c.creada_en, c.solicitud_uuid;
