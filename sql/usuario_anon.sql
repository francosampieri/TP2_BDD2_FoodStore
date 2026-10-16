-- ============================================================
-- usuario_anon — TP Unidad 5, Parte D (protección de datos)
--
-- Base objetivo: foodstore_tp_u5 (PostgreSQL 17), EXCLUSIVAMENTE.
--
-- OBJETIVO
--   Construir una copia ANONIMIZADA de la tabla usuario con datos
--   sintéticos DETERMINISTAS (mismo id_usuario -> mismo valor
--   sintético, siempre), de modo que los AGREGADOS de negocio sigan
--   siendo comparables contra la tabla real.
--
-- MAPEO (según lo pedido):
--   - nombre_usuario -> valor sintético derivado de id_usuario
--   - apellido       -> valor sintético derivado de id_usuario
--   - mail           -> valor sintético derivado de id_usuario
--   - celular        -> NULL
--   - contrasena     -> 'hash_no_valido'
--   - rol            -> SIN CAMBIOS (para comparar agregados)
--   - eliminado      -> SIN CAMBIOS
--   - created_at     -> SIN CAMBIOS
--   - id_usuario     -> se conserva como clave (no es dato personal
--                        directo y permite el cruce determinista)
--
-- NOTA SOBRE EL PATRÓN DETERMINISTA
--   El enunciado dice "siguiendo el patrón visto en clase", pero ese
--   material no está en el repositorio. Se usa este patrón explícito y
--   reproducible:
--       nombre_usuario = 'Usuario'  || id_usuario
--       apellido       = 'Apellido' || id_usuario
--       mail           = 'usuario' || id_usuario || '@anon.invalid'
--   Si el equipo conserva el patrón exacto de la Clase 2, reemplazar
--   las tres expresiones del BLOQUE 3 por el equivalente. Lo esencial es
--   que sean DETERMINISTAS y dependan SOLO de id_usuario.
--
-- PRIVACIDAD
--   Este script NUNCA lee ni projecta los valores originales de
--   nombre_usuario, apellido, mail, celular ni contrasena. Solo lee
--   id_usuario, rol, eliminado y created_at. Por lo tanto no muestra ni
--   exporta datos personales.
--
-- SEGURIDAD DE EJECUCIÓN
--   - NO usa DROP ni TRUNCATE.
--   - Si usuario_anon ya existe, el script se DETIENE (BLOQUE 1) sin
--     borrarla ni sobrescribirla.
--   - La creación y carga van en UNA transacción (todo o nada).
--
-- Ejecutar bloque por bloque en DBeaver, CONECTADO a foodstore_tp_u5.
-- ============================================================


-- ============================================================
-- BLOQUE 1 — GUARDAS (no crea ni borra nada)
-- 1) Debe ser foodstore_tp_u5.
-- 2) usuario_anon NO debe existir todavía. Si existe, se aborta.
-- ============================================================

-- 1.1 Vista previa (solo lectura): esperado NULL si la tabla no existe.
SELECT to_regclass('public.usuario_anon') AS usuario_anon_existente;

-- 1.2 Guarda dura: aborta ANTES de crear nada.
DO $$
BEGIN
    IF current_database() <> 'foodstore_tp_u5' THEN
        RAISE EXCEPTION
            'Script abortado: conectar a foodstore_tp_u5 (actual: %)',
            current_database();
    END IF;

    IF to_regclass('public.usuario_anon') IS NOT NULL THEN
        RAISE EXCEPTION
            'Script detenido: la tabla usuario_anon ya existe. No se borra ni se sobrescribe. Revise manualmente antes de reintentar.';
    END IF;
END
$$;


-- ============================================================
-- BLOQUE 2 — CREAR LA ESTRUCTURA usuario_anon (vacía)
-- Se replica el esquema real de usuario (ver sql/schema.sql, 30-40)
-- pero id_usuario NO es IDENTITY: se copia tal cual del origen.
-- ============================================================

BEGIN;

CREATE TABLE public.usuario_anon (
    id_usuario      BIGINT       NOT NULL PRIMARY KEY,
    nombre_usuario  VARCHAR(80)  NOT NULL,
    apellido        VARCHAR(80)  NOT NULL,
    mail            VARCHAR(120) NOT NULL UNIQUE,
    celular         VARCHAR(30),
    contrasena      VARCHAR(255) NOT NULL,
    rol             rol          NOT NULL,
    eliminado       BOOLEAN      NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL
);


-- ============================================================
-- BLOQUE 3 — CARGA ANONIMIZADA DETERMINISTA
-- Solo se leen id_usuario, rol, eliminado, created_at.
-- Las columnas personales se REEMPLAZAN por expresiones derivadas.
-- ============================================================

INSERT INTO public.usuario_anon
    (id_usuario, nombre_usuario, apellido, mail,
     celular, contrasena, rol, eliminado, created_at)
SELECT
    u.id_usuario,
    'Usuario'  || u.id_usuario,                     -- nombre sintético determinista
    'Apellido' || u.id_usuario,                     -- apellido sintético determinista
    'usuario'  || u.id_usuario || '@anon.invalid',  -- mail sintético determinista
    NULL,                                           -- celular: se descarta
    'hash_no_valido',                               -- contraseña inválida a propósito
    u.rol,                                          -- SIN CAMBIOS
    u.eliminado,                                    -- SIN CAMBIOS
    u.created_at                                    -- SIN CAMBIOS
FROM public.usuario AS u;

-- Chequeo de volumen (NO es dato personal): las dos filas deben coincidir.
SELECT (SELECT count(*) FROM public.usuario)      AS usuario_filas,
       (SELECT count(*) FROM public.usuario_anon) AS usuario_anon_filas;

COMMIT;


-- ============================================================
-- BLOQUE 4 — CONSULTA DE AGREGACIÓN SOBRE LA TABLA REAL `usuario`
-- Cantidad de usuarios por: rol, mes de created_at y eliminado.
-- (El resultado NO expone filas individuales ni datos personales.)
-- ============================================================

SELECT u.rol,
       date_trunc('month', u.created_at) AS mes_alta,
       u.eliminado,
       count(*)                          AS cantidad_usuarios
FROM   public.usuario AS u
GROUP  BY u.rol, date_trunc('month', u.created_at), u.eliminado
ORDER  BY u.rol, mes_alta, u.eliminado;

-- Resultado real (completar tras ejecutar en DBeaver):
-- ______________________________________________________________


-- ============================================================
-- BLOQUE 5 — CONSULTA EQUIVALENTE SOBRE usuario_anon
-- MISMA forma de agrupación; debe producir EXACTAMENTE los mismos
-- conteos que el BLOQUE 4.
-- ============================================================

SELECT a.rol,
       date_trunc('month', a.created_at) AS mes_alta,
       a.eliminado,
       count(*)                          AS cantidad_usuarios
FROM   public.usuario_anon AS a
GROUP  BY a.rol, date_trunc('month', a.created_at), a.eliminado
ORDER  BY a.rol, mes_alta, a.eliminado;

-- Resultado real (completar tras ejecutar en DBeaver):
-- ______________________________________________________________


-- ============================================================
-- BLOQUE 6 — VERIFICACIÓN DE EQUIVALENCIA CON EXCEPT (AMBAS DIRECCIONES)
-- Compara TODAS las columnas agregadas (rol, mes, eliminado, conteo).
-- Esperado en ambos sentidos: 0 filas.
-- ============================================================

-- 6.1 Filas del agregado real que NO están en el anonimizado.
--     Si devuelve filas -> la anonimización alteró los agregados.
(
    SELECT rol, date_trunc('month', created_at) AS mes_alta, eliminado,
           count(*) AS cantidad_usuarios
    FROM   public.usuario
    GROUP  BY rol, date_trunc('month', created_at), eliminado
)
EXCEPT
(
    SELECT rol, date_trunc('month', created_at) AS mes_alta, eliminado,
           count(*) AS cantidad_usuarios
    FROM   public.usuario_anon
    GROUP  BY rol, date_trunc('month', created_at), eliminado
);
-- Resultado real (completar): filas = ____   (esperado 0)

-- 6.2 Filas del agregado anonimizado que NO están en el real.
(
    SELECT rol, date_trunc('month', created_at) AS mes_alta, eliminado,
           count(*) AS cantidad_usuarios
    FROM   public.usuario_anon
    GROUP  BY rol, date_trunc('month', created_at), eliminado
)
EXCEPT
(
    SELECT rol, date_trunc('month', created_at) AS mes_alta, eliminado,
           count(*) AS cantidad_usuarios
    FROM   public.usuario
    GROUP  BY rol, date_trunc('month', created_at), eliminado
);
-- Resultado real (completar): filas = ____   (esperado 0)


-- ============================================================
-- QUÉ DEJA ESTE SCRIPT (resumen)
-- ------------------------------------------------------------
-- - usuario_anon con la misma estructura y volumen que usuario.
-- - Columnas personales reemplazadas por valores sintéticos
--   deterministas; celular = NULL; contrasena = 'hash_no_valido'.
-- - rol, eliminado y created_at intactos -> agregados comparables.
-- - Sin DROP/TRUNCATE y con guarda de existencia que impide
--   sobrescribir una tabla previa.
--
-- LO QUE NO HACE: no modifica usuario, no borra nada y no exporta
-- datos personales.
-- ============================================================
