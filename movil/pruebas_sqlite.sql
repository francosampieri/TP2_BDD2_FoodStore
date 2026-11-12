-- pruebas_sqlite.sql
-- Demostraciones: C1 (catálogo offline), C7 (atomicidad/CHECK/FK), REQ-02 (tx y rollback)
-- Ejecutar en SQLite 3.37+ sobre una base creada con movil/schema_sqlite.sql
-- y con producto_cache cargado desde la instantánea real (cargar_snapshot.sql).
-- Requiere PRAGMA foreign_keys = ON (ya en schema; se refuerza aquí).
-- NO inserta productos ficticios: usa el catálogo importado.

PRAGMA foreign_keys = ON;

-- Verificación previa: debe existir catálogo importado
SELECT producto_id, nombre, precio_centavos, stock_visto, disponible_visto, eliminado
FROM producto_cache
WHERE eliminado = 0 AND disponible_visto = 1
ORDER BY producto_id;

-- Producto de prueba tomado del catálogo real (sin alterar producto_cache)
DROP TABLE IF EXISTS temp._test_prod;
CREATE TEMP TABLE _test_prod AS
SELECT producto_id, precio_centavos
FROM producto_cache
WHERE eliminado = 0 AND disponible_visto = 1
ORDER BY producto_id
LIMIT 1;

-- ============================================================
-- BLOQUE A — TRANSACCIÓN EXITOSA (REQ-02)
-- ============================================================
BEGIN;

INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
VALUES ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 2, 'EFECTIVO');

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', producto_id, 2, precio_centavos
FROM temp._test_prod;

INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('b1c2d3e4-f5a6-4b7c-8d9e-0f1a2b3c4d5e',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        'PENDIENTE');

COMMIT;

-- Muestra las tres filas recién creadas
SELECT 'pedido_borrador' AS tabla, id_local, usuario_id_servidor, forma_pago
FROM pedido_borrador
WHERE id_local = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

SELECT 'item_borrador' AS tabla, id_local, producto_id, cantidad, precio_centavos_visto
FROM item_borrador
WHERE id_local = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

SELECT 'cola_sync' AS tabla, solicitud_uuid, id_local, estado, motivo
FROM cola_sync
WHERE id_local = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

-- ============================================================
-- BLOQUE B — ROLLBACK (REQ-02)
-- ============================================================
BEGIN;

INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
VALUES ('c2d3e4f5-a6b7-4c8d-9e0f-1a2b3c4d5e6f', 2, 'EFECTIVO');

ROLLBACK;

-- Debe devolver 0
SELECT COUNT(*) AS conteo_tras_rollback
FROM pedido_borrador
WHERE id_local = 'c2d3e4f5-a6b7-4c8d-9e0f-1a2b3c4d5e6f';

-- ============================================================
-- BLOQUE C — Caso C1 (REQ-01)
-- Esta consulta funciona sin conexión a PostgreSQL.
-- ============================================================
SELECT producto_id, nombre, precio, stock_visto
FROM v_catalogo_disponible
ORDER BY producto_id;

-- ============================================================
-- BLOQUE D — Caso C7 (REQ-02): INTENTOS QUE DEBEN FALLAR
-- IMPORTANTE: ejecutar cada sub-bloque de forma AISLADA (copiar/pegar
-- en sqlite3) para que el error esperado no interrumpa otras pruebas.
-- No ejecutar estos INSERT inválidos como parte de un lote exitoso.
-- ============================================================

-- ---- D1: cantidad = 0 (debe fallar por CHECK cantidad > 0) ----
-- EJECUTAR APARTE (usa un producto real del catálogo importado):
-- PRAGMA foreign_keys = ON;
-- DROP TABLE IF EXISTS temp._test_prod;
-- CREATE TEMP TABLE _test_prod AS
--   SELECT producto_id, precio_centavos FROM producto_cache
--   WHERE eliminado=0 AND disponible_visto=1 ORDER BY producto_id LIMIT 1;
-- BEGIN;
-- INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
-- VALUES ('d7000000-0000-4000-8000-000000000001', 2, 'EFECTIVO');
-- INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
-- SELECT 'd7000000-0000-4000-8000-000000000001', producto_id, 0, precio_centavos
-- FROM temp._test_prod;
-- -- Se espera error: CHECK constraint failed
-- ROLLBACK;
-- SELECT COUNT(*) AS debe_ser_0
-- FROM pedido_borrador
-- WHERE id_local = 'd7000000-0000-4000-8000-000000000001';
-- SELECT COUNT(*) AS items_debe_ser_0
-- FROM item_borrador
-- WHERE id_local = 'd7000000-0000-4000-8000-000000000001';

-- ---- D2: producto inexistente (debe fallar por FK con PRAGMA foreign_keys=ON) ----
-- EJECUTAR APARTE:
-- PRAGMA foreign_keys = ON;
-- BEGIN;
-- INSERT INTO pedido_borrador (id_local, usuario_id_servidor, forma_pago)
-- VALUES ('d7000000-0000-4000-8000-000000000002', 2, 'EFECTIVO');
-- INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
-- VALUES ('d7000000-0000-4000-8000-000000000002', 99999, 1, 150000);
-- -- Se espera error: FOREIGN KEY constraint failed
-- ROLLBACK;
-- SELECT COUNT(*) AS debe_ser_0
-- FROM pedido_borrador
-- WHERE id_local = 'd7000000-0000-4000-8000-000000000002';
-- SELECT COUNT(*) AS items_debe_ser_0
-- FROM item_borrador
-- WHERE id_local = 'd7000000-0000-4000-8000-000000000002';
