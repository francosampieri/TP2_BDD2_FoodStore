-- ============================================================================
-- TP Unidad 4 — Parte 4: Migración reversible ControlLoteAlmacen -> R1/R2
-- Base de ejecución: foodstore_tp_u4_mig  (copia NUEVA de foodstore_tp5)
--
-- NUNCA ejecutar en foodstore, foodstore_tp2, foodstore_tp3, foodstore_tp4,
-- foodstore_tp5 ni foodstore_tp_u4.
--
-- Creación previa de la copia (NO ejecutar desde este script):
--   CREATE DATABASE foodstore_tp_u4_mig TEMPLATE foodstore_tp5;
-- Luego conectarse a foodstore_tp_u4_mig y no cambiar de conexión durante
-- toda la sesión.
--
-- Objetivo:
--   Migrar la relación original no-FNBC control_lote_almacen a la
--   descomposición FNBC R1 (responsable -> depósito) y R2 (lote -> responsable),
--   conservando los IDs literales de la consigna (30/31, 501/502/503, 801/802)
--   y la tabla original como fuente de reversión.
--
-- Estructura:
--   0) Guarda de base activa (aborta si no es foodstore_tp_u4_mig).
--   1) Precondiciones (usuarios vigentes y objetos ausentes) ANTES del BEGIN.
--   2) Un único BEGIN con todo el DDL/DML (bloques A-G).
--   3) Bloque G: DO que lanza excepción si algún EXCEPT devuelve filas.
--   4) Consultas de revisión (Revisión 1 a 5).
--   5) COMMIT y ROLLBACK comentados: elegir UNO manualmente en la misma
--      conexión de DBeaver después de revisar los resultados.
--   6) Reversión post-COMMIT documentada como bloque NO ejecutable.
--
-- Nota: el DDL en PostgreSQL es transaccional. Si algo falla dentro del BEGIN,
-- la transacción queda abortada y el operador debe ejecutar ROLLBACK
-- manualmente en la MISMA conexión; la base vuelve al estado previo.
-- ============================================================================


-- ============================================================================
-- 0) GUARDA DE BASE ACTIVA
-- ============================================================================
-- Aborta si la conexión actual no es la copia de prueba.
-- Si la copia se creó con otro nombre, ajustar el literal de esta guarda.
DO $$
BEGIN
    IF current_database() <> 'foodstore_tp_u4_mig' THEN
        RAISE EXCEPTION
            'Este script solo puede ejecutarse en foodstore_tp_u4_mig (base actual: %)',
            current_database();
    END IF;
END;
$$;


-- ============================================================================
-- 1) PRECONDICIONES (verificar ANTES de abrir la transacción)
-- ============================================================================
-- P2: los usuarios 1 y 2 existen y están vigentes (eliminado = FALSE).
DO $$
DECLARE
    v_usuarios INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_usuarios
    FROM   usuario
    WHERE  id_usuario IN (1, 2)
      AND  eliminado = FALSE;

    IF v_usuarios <> 2 THEN
        RAISE EXCEPTION
            'Precondición P2 fallida: se esperaban 2 usuarios vigentes (id 1 y 2), encontrados %',
            v_usuarios;
    END IF;
END;
$$;

-- P3-P10: ninguno de los objetos que crea la migración debe existir ya.
DO $$
DECLARE
    v_existentes TEXT;
BEGIN
    SELECT string_agg(nombre, ', ')
    INTO   v_existentes
    FROM  (VALUES
              ('public.control_lote_almacen'),
              ('public.tp_u4_deposito'),
              ('public.tp_u4_lote'),
              ('public.tp_u4_responsable_control'),
              ('public.tp_u4_responsable_usuario'),
              ('public.tp_u4_r1_responsable_deposito'),
              ('public.tp_u4_r2_lote_responsable'),
              ('public.tp_u4_v_control_lote_almacen')
          ) AS t(nombre)
    WHERE to_regclass(nombre) IS NOT NULL;

    IF v_existentes IS NOT NULL THEN
        RAISE EXCEPTION
            'Precondición fallida: ya existen objetos que la migración espera crear: %',
            v_existentes;
    END IF;
END;
$$;


-- ============================================================================
-- 2) MIGRACIÓN — TODO EL DDL/DML EN UN ÚNICO BEGIN
-- ============================================================================
BEGIN;

-- ----------------------------------------------------------------------------
-- Bloque A — Tablas maestras con IDs literales (SIN IDENTITY)
-- ----------------------------------------------------------------------------
CREATE TABLE tp_u4_deposito (
    id_deposito BIGINT PRIMARY KEY,          -- 30, 31 (literal, consigna)
    nombre      VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE tp_u4_lote (
    id_lote     BIGINT PRIMARY KEY,          -- 501, 502, 503 (literal, consigna)
    nombre      VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE tp_u4_responsable_control (
    id_responsable BIGINT PRIMARY KEY,       -- 801, 802 (literal, consigna)
    nombre         VARCHAR(80) NOT NULL UNIQUE
);

-- ----------------------------------------------------------------------------
-- Bloque B — Poblado de maestras y correspondencia con usuario
-- ----------------------------------------------------------------------------
INSERT INTO tp_u4_deposito (id_deposito, nombre) VALUES
    (30, 'Deposito A'),
    (31, 'Deposito B');

INSERT INTO tp_u4_lote (id_lote, nombre) VALUES
    (501, 'Lote 501'),
    (502, 'Lote 502'),
    (503, 'Lote 503');

INSERT INTO tp_u4_responsable_control (id_responsable, nombre) VALUES
    (801, 'Responsable 1'),
    (802, 'Responsable 2');

-- Correspondencia metadato: responsable literal 801/802 <-> usuario del seed.
CREATE TABLE tp_u4_responsable_usuario (
    id_responsable BIGINT NOT NULL PRIMARY KEY
                   REFERENCES tp_u4_responsable_control(id_responsable),
    id_usuario     BIGINT NOT NULL UNIQUE
                   REFERENCES usuario(id_usuario)
);

INSERT INTO tp_u4_responsable_usuario (id_responsable, id_usuario) VALUES
    (801, 1),
    (802, 2);

-- ----------------------------------------------------------------------------
-- Bloque C — Relación original con FKs hacia las maestras
-- ----------------------------------------------------------------------------
CREATE TABLE control_lote_almacen (
    lote_id                BIGINT NOT NULL REFERENCES tp_u4_lote(id_lote),
    deposito_id            BIGINT NOT NULL REFERENCES tp_u4_deposito(id_deposito),
    responsable_control_id BIGINT NOT NULL REFERENCES tp_u4_responsable_control(id_responsable),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);

-- ----------------------------------------------------------------------------
-- Bloque D — R1 y R2 (descomposición FNBC)
-- ----------------------------------------------------------------------------
CREATE TABLE tp_u4_r1_responsable_deposito (
    responsable_control_id BIGINT NOT NULL PRIMARY KEY
                           REFERENCES tp_u4_responsable_control(id_responsable),
    deposito_id            BIGINT NOT NULL
                           REFERENCES tp_u4_deposito(id_deposito)
);

CREATE TABLE tp_u4_r2_lote_responsable (
    lote_id                BIGINT NOT NULL REFERENCES tp_u4_lote(id_lote),
    responsable_control_id BIGINT NOT NULL
                           REFERENCES tp_u4_r1_responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);

-- ----------------------------------------------------------------------------
-- Bloque E — Migración desde la tabla original (IDs literales, sin CTEs)
-- ----------------------------------------------------------------------------
INSERT INTO tp_u4_r1_responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM   control_lote_almacen;

INSERT INTO tp_u4_r2_lote_responsable (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM   control_lote_almacen;

-- ----------------------------------------------------------------------------
-- Bloque F — Vista de compatibilidad (R2 JOIN R1)
-- ----------------------------------------------------------------------------
CREATE VIEW tp_u4_v_control_lote_almacen AS
SELECT
    r2.lote_id                AS lote_id,
    r1.deposito_id            AS deposito_id,
    r2.responsable_control_id AS responsable_control_id
FROM   tp_u4_r2_lote_responsable r2
JOIN   tp_u4_r1_responsable_deposito r1
    ON r1.responsable_control_id = r2.responsable_control_id;

-- ----------------------------------------------------------------------------
-- Bloque G — Validación EXCEPT bidireccional
-- Si alguna dirección devuelve filas, se lanza una excepción y la transacción
-- queda abortada: ejecutar ROLLBACK manualmente en la misma conexión.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_diff_a INTEGER;
    v_diff_b INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_diff_a
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   tp_u4_v_control_lote_almacen
    ) t;

    SELECT COUNT(*) INTO v_diff_b
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   tp_u4_v_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM   control_lote_almacen
    ) t;

    IF v_diff_a > 0 OR v_diff_b > 0 THEN
        RAISE EXCEPTION
            'Validación EXCEPT fallida: dirección A = %, dirección B = %',
            v_diff_a, v_diff_b;
    END IF;

    RAISE NOTICE 'Validación EXCEPT OK: dirección A = 0, dirección B = 0';
END;
$$;

-- ----------------------------------------------------------------------------
-- Consultas de revisión (dentro de la transacción, antes de decidir)
-- ----------------------------------------------------------------------------
-- Revisión 1 — tabla original (esperado: 3 filas)
SELECT * FROM control_lote_almacen ORDER BY lote_id;

-- Revisión 2 — vista reconstruida (esperado: 3 filas idénticas a Revisión 1)
SELECT * FROM tp_u4_v_control_lote_almacen ORDER BY lote_id;

-- Revisión 3 — R1 (esperado: 2 filas: (801,30), (802,31))
SELECT * FROM tp_u4_r1_responsable_deposito ORDER BY responsable_control_id;

-- Revisión 4 — R2 (esperado: 3 filas: (501,801), (502,801), (503,802))
SELECT * FROM tp_u4_r2_lote_responsable ORDER BY lote_id;

-- Revisión 5 — correspondencia responsable <-> usuario (esperado: 2 filas)
SELECT id_responsable, id_usuario
FROM   tp_u4_responsable_usuario
ORDER  BY id_responsable;

-- ----------------------------------------------------------------------------
-- Decisión manual: elegir UNA de las dos opciones en la MISMA conexión
-- ----------------------------------------------------------------------------
-- COMMIT;
-- ROLLBACK;


-- ============================================================================
-- 3) REVERSIÓN POST-COMMIT — BLOQUE NO EJECUTABLE
-- ============================================================================
-- Ejecutar manualmente SOLO después de un COMMIT exitoso, si se desea volver
-- a la relación original. Orden obligatorio: vista -> R2 -> R1.
-- Sin CASCADE. NO se elimina control_lote_almacen ni sus tablas maestras
-- (tp_u4_deposito, tp_u4_lote, tp_u4_responsable_control,
--  tp_u4_responsable_usuario): son la fuente de reversión con los datos
-- originales y las correspondencias.
-- ============================================================================
-- BEGIN;
--   DROP VIEW  tp_u4_v_control_lote_almacen;
--   DROP TABLE tp_u4_r2_lote_responsable;
--   DROP TABLE tp_u4_r1_responsable_deposito;
-- COMMIT;
