-- ============================================================================
-- TP Unidad 4 — Parte 1: FNBC — ControlLoteAlmacen
-- Base de ejecución: foodstore_tp_u4  (NUNCA en foodstore, foodstore_tp5, etc.)
-- Propósito: descomponer la relación original no-FNBC en R1 y R2, migrar la
--            instancia de ejemplo y verificar la unión sin pérdida con una
--            vista de compatibilidad.
-- ----------------------------------------------------------------------------
-- Correcciones aplicadas respecto de specs/tp_u4/plan_fnbc_desnormalizacion.md:
--   * Las tablas maestras usan BIGINT PRIMARY KEY SIN IDENTITY: los IDs de la
--     consigna (lote 501/502/503, deposito 30/31, responsable 801/802) se
--     insertan como valores literales para conservarlos en todo el ejercicio.
--   * R1/R2 usan los IDs literales de la consigna (no se reemplazan por
--     id_usuario del esquema FoodStore).
--   * El vínculo 801/802 -> usuario.id_usuario se resuelve con una tabla de
--     correspondencia chica con FK a usuario, sin alterar las relaciones del
--     ejercicio.
--   * La auditoría EXCEPT compara la tabla ORIGINAL contra la VISTA (no
--     contra una repetición manual del mismo JOIN).
--   * Ejecutar por bloques (resaltar y ejecutar cada BLOQUE en DBeaver).
-- ============================================================================

-- >>> BLOQUE 1 — Tablas maestras (IDs explícitos, SIN IDENTITY) <<<
-- Resultado en DBeaver: mensajes "CREATE TABLE" / "Query succeed".
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

-- >>> BLOQUE 2 — Poblado de tablas maestras con los IDs literales <<<
-- Resultado en DBeaver: "INSERT 0 2" / "INSERT 0 3".
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

-- >>> BLOQUE 3 — Verificación previa: usuarios elegidos para la correspondencia <<<
-- Usuarios candidatos para mapear 801 y 802. EJECUTAR PRIMERO y copiar el
-- resultado al informe. Si las dos filas existen con eliminado = FALSE,
-- continuar con el BLOQUE 4. (En el seed de foodstore_tp_u4: id 1 = Admin
-- Garcia, id 2 = Ana Gomez.)
SELECT id_usuario, nombre_usuario, apellido, rol, eliminado
FROM   usuario
WHERE  id_usuario IN (1, 2)
ORDER  BY id_usuario;

-- >>> BLOQUE 4 — Tabla de correspondencia responsable (literal) <-> usuario <<<
-- Conecta 801/802 con usuario.id_usuario vía FK a usuario, SIN reemplazar los
-- IDs literales en las relaciones del ejercicio. Usar los id_usuario
-- verificados en el BLOQUE 3.
-- Para el informe: registrar que 801 <-> Admin Garcia (id 1) y 802 <-> Ana
-- Gomez (id 2).
CREATE TABLE tp_u4_responsable_usuario (
    id_responsable BIGINT NOT NULL PRIMARY KEY REFERENCES tp_u4_responsable_control(id_responsable),
    id_usuario     BIGINT NOT NULL UNIQUE REFERENCES usuario(id_usuario)
);

INSERT INTO tp_u4_responsable_usuario (id_responsable, id_usuario) VALUES
    (801, 1),
    (802, 2);

-- >>> BLOQUE 5 — Relación ORIGINAL (no-FNBC) con los IDs literales y FKs <<<
-- Misma estructura que la consigna, con las FKs pertinentes a las tablas
-- maestras. PK (lote_id, deposito_id).
-- Resultado: "CREATE TABLE".
CREATE TABLE control_lote_almacen (
    lote_id                BIGINT NOT NULL REFERENCES tp_u4_lote(id_lote),
    deposito_id            BIGINT NOT NULL REFERENCES tp_u4_deposito(id_deposito),
    responsable_control_id BIGINT NOT NULL REFERENCES tp_u4_responsable_control(id_responsable),
    PRIMARY KEY (lote_id, deposito_id)
);

-- >>> BLOQUE 6 — Instancia de ejemplo exacta de la consigna <<<
-- Resultado: "INSERT 0 3". Copiar las 3 filas al informe.
INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id) VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);

-- >>> BLOQUE 7 — R1: responsable de control por depósito <<<
-- R1(responsable_control_id, deposito_id), PK responsable_control_id.
-- Contiene la DF violatoria DF2 (responsable_control_id -> deposito_id).
CREATE TABLE tp_u4_r1_responsable_deposito (
    responsable_control_id BIGINT NOT NULL PRIMARY KEY REFERENCES tp_u4_responsable_control(id_responsable),
    deposito_id            BIGINT NOT NULL REFERENCES tp_u4_deposito(id_deposito)
);

-- >>> BLOQUE 8 — R2: asignación lote-responsable <<<
-- R2(lote_id, responsable_control_id), PK compuesta.
-- La FK a R1 garantiza que no puede asignarse un lote a un responsable sin
-- depósito registrado.
CREATE TABLE tp_u4_r2_lote_responsable (
    lote_id                BIGINT NOT NULL REFERENCES tp_u4_lote(id_lote),
    responsable_control_id BIGINT NOT NULL REFERENCES tp_u4_r1_responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);

-- >>> BLOQUE 9 — Migración de R1 y R2 desde la tabla original <<<
-- Como las maestras conservan los IDs literales, la migración es directa con
-- INSERT ... SELECT (sin JOIN por nombre).
-- Resultado: "INSERT 0 2" (R1) e "INSERT 0 3" (R2).
INSERT INTO tp_u4_r1_responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM   control_lote_almacen;

INSERT INTO tp_u4_r2_lote_responsable (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM   control_lote_almacen;

-- >>> BLOQUE 10 — Vista de compatibilidad (R2 JOIN R1) <<<
-- Devuelve EXACTAMENTE lote_id, deposito_id, responsable_control_id con los
-- IDs literales de la consigna.
CREATE VIEW tp_u4_v_control_lote_almacen AS
SELECT
    r2.lote_id                AS lote_id,
    r1.deposito_id            AS deposito_id,
    r2.responsable_control_id AS responsable_control_id
FROM   tp_u4_r2_lote_responsable r2
JOIN   tp_u4_r1_responsable_deposito r1
    ON r1.responsable_control_id = r2.responsable_control_id;

-- >>> BLOQUE 11 — Correspondencia visual original vs. reconstruido <<<
-- Esperado: 6 filas (3 del ORIGINAL y 3 del RECONSTRUIDO) alineadas por
-- lote_id. Copiar al informe.
SELECT lote_id, deposito_id, responsable_control_id, 'ORIGINAL' AS origen
FROM   control_lote_almacen
UNION ALL
SELECT lote_id, deposito_id, responsable_control_id, 'RECONSTRUIDO' AS origen
FROM   tp_u4_v_control_lote_almacen
ORDER  BY lote_id, origen;

-- >>> BLOQUE 12 — Mapeo de correspondencia con el esquema FoodStore <<<
-- Confirma el vínculo 801 <-> usuario 1 y 802 <-> usuario 2. Copiar al informe.
SELECT r.id_responsable, r.nombre    AS responsable,
       u.id_usuario,     u.nombre_usuario, u.apellido
FROM   tp_u4_responsable_control r
JOIN   tp_u4_responsable_usuario ru ON ru.id_responsable = r.id_responsable
JOIN   usuario u                     ON u.id_usuario      = ru.id_usuario
ORDER  BY r.id_responsable;

-- >>> BLOQUE 13 — Auditoría EXCEPT dirección A <<<
-- Filas en la tabla ORIGINAL ausentes en la vista. Esperado: 0 FILAS.
-- Copiar el resultado ("No rows affected" / 0 filas) al informe.
SELECT lote_id, deposito_id, responsable_control_id
FROM   control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM   tp_u4_v_control_lote_almacen;

-- >>> BLOQUE 14 — Auditoría EXCEPT dirección B <<<
-- Filas en la VISTA ausentes en la tabla original. Esperado: 0 FILAS.
-- Copiar el resultado al informe.
SELECT lote_id, deposito_id, responsable_control_id
FROM   tp_u4_v_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM   control_lote_almacen;

-- >>> CIERRE — Qué observar en DBeaver y copiar al informe <<<
-- 1) BLOQUE 3: filas usuario 1 y 2 vigentes.
-- 2) BLOQUE 11: 6 filas alineadas (3 originales + 3 reconstruidas).
-- 3) BLOQUE 12: mapeo 801->usuario 1, 802->usuario 2.
-- 4) BLOQUES 13 y 14: 0 filas cada uno (reunión sin pérdida sobre la
--    instancia de la consigna).
-- NOTA sobre DF1: la descomposición NO preserva automáticamente la DF
-- (lote_id, deposito_id) -> responsable_control_id. La reunión R1 JOIN R2 es
-- sin pérdida, pero mantener DF1 en el esquema descompuesto requiere control
-- adicional (trigger o lógica de aplicación); esto se documenta en el informe
-- y NO debe afirmarse como garantía automática de la descomposición.
-- ============================================================================