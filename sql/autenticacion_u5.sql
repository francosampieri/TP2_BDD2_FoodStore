-- ============================================================
-- AUTENTICACIÓN — TP Unidad 5, Parte C (preparación)
-- Reconstrucción de los artefactos faltantes de la Clase 2:
--   fn_autenticar  y  fn_resetear_password
--
-- Base objetivo: foodstore_tp_u5 (PostgreSQL 17).
--   p g c r y p t o se activa SOLO en esta base (es por base, no
--   por cluster). El resto de los objetos también quedan en esta base.
--
-- Contexto verificado antes de escribir este script:
--   - fn_autenticar y fn_resetear_password NO existen (grep negativo).
--   - pgcrypto 1.3 está DISPONIBLE en el servidor; installed_version
--     es NULL (no instalada todavía en foodstore_tp_u5).
--   - usuario.contrasena está HOY en texto plano (seed y carga masiva).
--   - app_web tiene PASSWORD NULL y solo puede leer
--     usuario.id_usuario y usuario.eliminado (rol_app_escritura).
--
-- Decisiones de diseño (ver informe_incidente.md / BITACORA.md):
--   - fn_autenticar NO compara texto plano. Primero busca el usuario
--     vigente y su hash; LUEGO valida en PL/pgSQL que sea un bcrypt
--     bien formado y solo entonces llama a crypt. No depende del orden
--     de evaluación de los AND del WHERE.
--   - SECURITY DEFINER con owners NOLOGIN de mínimos privilegios y
--     SEPARADOS por función:
--       * rol_auth        -> fn_autenticar       (solo SELECT).
--       * rol_auth_reset  -> fn_resetear_password (SELECT + UPDATE).
--     El privilegio UPDATE(contrasena) NO se le da a rol_auth.
--   - Creación, cambio de propietario, REVOKE y GRANT se agrupan en
--     UNA transacción para no dejar una ventana en la que una función
--     quede con el EXECUTE por defecto de PUBLIC.
--   - fn_resetear_password NO se otorga a app_web, admin_datos ni
--     soporte en este TP.
--
-- Este script NO contiene contraseñas reales, NO consulta ni imprime
-- valores existentes de usuario.contrasena, NO hace COMMIT de datos y
-- NO ejecuta DROP.
--
-- Ejecutar bloque por bloque en DBeaver, CONECTADO a foodstore_tp_u5.
-- El BLOQUE 2 crea roles, que son metadato de TODO EL CLUSTER (igual
-- criterio que roles.sql, BLOQUE 1).
-- ============================================================


-- ============================================================
-- BLOQUE 0 — GUARDA DE BASE Y DIAGNÓSTICO PREVIO (solo lectura)
-- ============================================================

-- 0.1 Abortar si no estamos conectados a foodstore_tp_u5.
DO $$
BEGIN
    IF current_database() <> 'foodstore_tp_u5' THEN
        RAISE EXCEPTION
            'Script abortado: conectar a foodstore_tp_u5 (actual: %)',
            current_database();
    END IF;
END
$$;

-- 0.2 Estado de pgcrypto antes de instalar (esperado: NO aparece fila).
SELECT e.extname, e.extversion
FROM   pg_extension e
WHERE  e.extname = 'pgcrypto';

-- 0.3 ¿La extensión está disponible para instalar? (no asumir).
SELECT a.name, a.default_version, a.installed_version
FROM   pg_available_extensions a
WHERE  a.name = 'pgcrypto';

-- 0.4 Owner del esquema public y owner de la base: se necesitan para
--     CREATE EXTENSION (pgcrypto es una extensión "trusted": puede
--     instalarla el owner de la base; NO asumir superusuario).
SELECT n.nspname, r.rolname AS owner_esquema
FROM   pg_namespace n
JOIN   pg_roles r ON r.oid = n.nspowner
WHERE  n.nspname = 'public';

SELECT d.datname, pg_get_userbyid(d.datdba) AS owner_base
FROM   pg_database d
WHERE  d.datname = current_database();


-- ============================================================
-- BLOQUE 1 — INSTALAR pgcrypto SOLO EN foodstore_tp_u5
-- pgcrypto queda disponible como public.crypt(...) y public.gen_salt(...).
-- Idempotencia: si ya estuviera instalada, esta sentencia falla con
-- "extension already exists"; en ese caso NO re-ejecutar y seguir.
-- ============================================================

CREATE EXTENSION pgcrypto WITH SCHEMA public;

-- Verificación inmediata (esperado: una fila, extversion 1.3).
SELECT e.extname, e.extversion
FROM   pg_extension e
WHERE  e.extname = 'pgcrypto';


-- ============================================================
-- BLOQUE 2 — DOS ROLES PROPIETARIOS NOLOGIN, DE MÍNIMOS PRIVILEGIOS
-- ALCANCE: TODO EL CLUSTER (igual que roles.sql, BLOQUE 1).
-- Idempotencia: si el rol ya existe, CREATE ROLE falla; no se
-- incluye DROP para no borrar un rol con objetos vivos.
--
-- Separación por función: fn_autenticar (SILENCIOSA sobre datos que
-- escribe) no necesita UPDATE; fn_resetear_password sí lo necesita.
-- Así, si una función se ve comprometida, el alcance de cada owner es
-- el mínimo indispensable.
-- ============================================================

-- 2.1 Owner de fn_autenticar: SOLO lectura.
CREATE ROLE rol_auth NOLOGIN;
GRANT USAGE ON SCHEMA public TO rol_auth;
GRANT SELECT (id_usuario, mail, contrasena, eliminado)
      ON public.usuario TO rol_auth;

-- 2.2 Owner de fn_resetear_password: lectura de la clave de búsqueda
--     (mail, eliminado) + UPDATE de la única columna que reescribe.
--     No se le otorga SELECT sobre contrasena: no la lee.
CREATE ROLE rol_auth_reset NOLOGIN;
GRANT USAGE ON SCHEMA public TO rol_auth_reset;
GRANT SELECT (mail, eliminado) ON public.usuario TO rol_auth_reset;
GRANT UPDATE (contrasena)      ON public.usuario TO rol_auth_reset;

-- NOTA (decisión a revisar): UPDATE (contrasena) es una ampliación de
-- permisos acotada a UNA columna y otorgada SOLO al owner NOLOGIN de
-- fn_resetear_password (no a rol_auth, no a roles de aplicación). Si el
-- equipo decide NO habilitarla, entonces fn_resetear_password no debe
-- crearse (ver BLOQUE 3).


-- ============================================================
-- BLOQUE 3 — CREAR FUNCIONES Y FIJAR PERMISOS EN UNA SOLA TRANSACCIÓN
--
-- MOTIVO (punto: evitar ventana de acceso público):
--   Al crear una función, PostgreSQL concede EXECUTE a PUBLIC por
--   defecto. Si se creara y luego se revocara fuera de una
--   transacción, existiría una ventana entre ambos pasos. Dentro de
--   UNA transacción, otra sesión NO ve la función hasta el COMMIT, y
--   al confirmar ya está revocado el EXECUTE de PUBLIC: la ventana
--   no existe.
--
--   (En este cluster podría no haber ventana igualmente si roles.sql
--   §2.6, ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON ROUTINES
--   FROM PUBLIC, alcanzó a las rutinas creadas por este mismo rol.
--   Como eso NO está garantizado —depende de qué rol lo ejecutó y en
--   qué base—, se cierra la ventana de forma explícita con la
--   transacción.)
-- ============================================================

BEGIN;

-- ---- 3.1 fn_autenticar ----
-- Compara contraseñas HASHEADAS (crypt), ignora usuarios eliminados y
-- devuelve el id_usuario en caso de éxito o NULL en caso de fallo.
--
-- Seguridad:
--   * SECURITY DEFINER: corre como rol_auth, así app_web NO necesita
--     leer usuario.contrasena.
--   * search_path fijo a pg_catalog y objetos calificados
--     (public.usuario, public.crypt) para evitar el ataque de
--     search_path sobre funciones SECURITY DEFINER.
--   * NO depende del orden de evaluación de los AND: primero obtiene
--     el hash y recién después, tras validar el formato bcrypt, llama
--     a crypt. Un valor heredado en texto plano devuelve NULL sin
--     error y sin autenticarse.
--   * Registra SOLO el resultado (nunca la contraseña ni el mail).
CREATE FUNCTION public.fn_autenticar(
    p_mail       TEXT,
    p_contrasena TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
    v_id_usuario BIGINT;
    v_hash       TEXT;
BEGIN
    -- 1) Buscar el usuario vigente y su hash, SIN evaluar crypt aún.
    SELECT u.id_usuario, u.contrasena
      INTO v_id_usuario, v_hash
      FROM public.usuario AS u
     WHERE u.mail = p_mail
       AND u.eliminado = FALSE;

    IF v_id_usuario IS NULL THEN
        RAISE LOG 'fn_autenticar: intento resultado=FALLO';
        RETURN NULL;
    END IF;

    -- 2) Validar EXPLÍCITAMENTE que el valor almacenado sea un bcrypt
    --    bien formado ANTES de llamar a crypt. Regex sin backslashes
    --    (usa [$] en lugar de \$ ) para no depender de
    --    standard_conforming_strings. Formato: $2a$/$2b$/$2y$ +
    --    costo de 2 dígitos + 53 caracteres de base64 bcrypt.
    IF v_hash IS NULL
       OR v_hash !~ '^[$]2[aby][$][0-9]{2}[$][./A-Za-z0-9]{53}$' THEN
        -- Contraseña heredada en texto plano (o formato inválido):
        -- no autentica y no genera error.
        RAISE LOG 'fn_autenticar: intento resultado=FALLO';
        RETURN NULL;
    END IF;

    -- 3) Comparar contra el hash (sal bcrypt ya validada).
    IF v_hash = public.crypt(p_contrasena, v_hash) THEN
        RAISE LOG 'fn_autenticar: intento resultado=OK';
        RETURN v_id_usuario;
    END IF;

    RAISE LOG 'fn_autenticar: intento resultado=FALLO';
    RETURN NULL;
END;
$$;

ALTER FUNCTION public.fn_autenticar(text, text) OWNER TO rol_auth;

-- ---- 3.2 fn_resetear_password ----
-- Rehashea con crypt + gen_salt('bf') y actualiza SOLO la fila del
-- mail indicado y no eliminado. Owner: rol_auth_reset.
--   * Devuelve TRUE/FALSE; NO devuelve ni registra la contraseña.
--   * NO se otorga su ejecución a app_web, admin_datos ni soporte.
--     Queda ejecutable solo por el owner y por superusuarios. Si el
--     equipo necesita una vía administrativa, debe definirse un rol
--     dedicado con su propio GRANT (decisión, no incluida aquí).
CREATE FUNCTION public.fn_resetear_password(
    p_mail             TEXT,
    p_nueva_contrasena TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
    v_afectadas INTEGER;
BEGIN
    UPDATE public.usuario
       SET contrasena = public.crypt(p_nueva_contrasena, public.gen_salt('bf'))
     WHERE mail      = p_mail
       AND eliminado = FALSE;

    GET DIAGNOSTICS v_afectadas = ROW_COUNT;

    -- Solo el conteo; nunca la contraseña.
    RAISE LOG 'fn_resetear_password: filas_actualizadas=%', v_afectadas;

    RETURN v_afectadas = 1;
END;
$$;

ALTER FUNCTION public.fn_resetear_password(text, text) OWNER TO rol_auth_reset;

-- ---- 3.3 Permisos de cada owner sobre las funciones de pgcrypto ----
-- El owner ejecuta crypt/gen_salt DENTRO de la función SECURITY
-- DEFINER y por eso necesita EXECUTE sobre ellas.
--
-- Decisión a revisar: normalmente PUBLIC ya tiene EXECUTE, pero
-- roles.sql §2.6 aplica ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON
-- ROUTINES FROM PUBLIC. Si esa política alcanzó también a pgcrypto,
-- sin estos GRANT el owner NO podría ejecutar crypt y la autenticación
-- fallaría en tiempo de ejecución. Verificar con el BLOQUE 4.2; si el
-- resultado ya es TRUE, estos GRANT son redundantes. NO se otorgan a
-- ningún rol de aplicación.
GRANT EXECUTE ON FUNCTION public.crypt(text, text) TO rol_auth, rol_auth_reset;
GRANT EXECUTE ON FUNCTION public.gen_salt(text)    TO rol_auth_reset;

-- ---- 3.4 Cerrar la ventana de PUBLIC antes del COMMIT ----
REVOKE EXECUTE ON FUNCTION public.fn_autenticar(text, text)        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_resetear_password(text, text) FROM PUBLIC;

-- ---- 3.5 Único llamador habilitado para autenticar: app_web ----
GRANT EXECUTE ON FUNCTION public.fn_autenticar(text, text) TO app_web;

COMMIT;


-- ============================================================
-- BLOQUE 4 — VERIFICACIONES (solo lectura)
-- ============================================================

-- 4.1 Privilegios por función (esperado):
--   app_web_puede_autenticar    = true
--   app_web_puede_resetear      = false
--   admin_datos_puede_resetear  = false
--   soporte_puede_resetear      = false
SELECT has_function_privilege('app_web','public.fn_autenticar(text,text)','EXECUTE')
           AS app_web_puede_autenticar,
       has_function_privilege('app_web','public.fn_resetear_password(text,text)','EXECUTE')
           AS app_web_puede_resetear,
       has_function_privilege('admin_datos','public.fn_resetear_password(text,text)','EXECUTE')
           AS admin_datos_puede_resetear,
       has_function_privilege('rol_soporte','public.fn_resetear_password(text,text)','EXECUTE')
           AS soporte_puede_resetear;

-- 4.2 Privilegios de los owners sobre pgcrypto (esperado: todo true).
SELECT has_function_privilege('rol_auth','public.crypt(text,text)','EXECUTE')
           AS rol_auth_puede_crypt,
       has_function_privilege('rol_auth_reset','public.crypt(text,text)','EXECUTE')
           AS rol_auth_reset_puede_crypt,
       has_function_privilege('rol_auth_reset','public.gen_salt(text)','EXECUTE')
           AS rol_auth_reset_puede_gensalt;

-- 4.3 Propiedad y modo SECURITY (esperado: prosecdef = true;
--     owner fn_autenticar = rol_auth; owner fn_resetear = rol_auth_reset).
SELECT p.proname,
       p.prosecdef                       AS security_definer,
       pg_get_userbyid(p.proowner)       AS propietario,
       pg_get_function_identity_arguments(p.oid) AS argumentos
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fn_autenticar', 'fn_resetear_password')
ORDER  BY p.proname;

-- 4.4 Grantees por rutina: PUBLIC NO debe aparecer; fn_autenticar debe
--     mostrar EXECUTE para app_web; fn_resetear_password no debe
--     mostrar ningún rol de aplicación.
SELECT rp.grantee, rp.routine_name, rp.privilege_type
FROM   information_schema.routine_privileges rp
WHERE  rp.routine_schema = 'public'
  AND  rp.routine_name IN ('fn_autenticar', 'fn_resetear_password')
ORDER  BY rp.routine_name, rp.grantee;

-- 4.5 Privilegios de columna de cada owner sobre usuario:
--     rol_auth       -> SELECT (id_usuario, mail, contrasena, eliminado)
--     rol_auth_reset -> SELECT (mail, eliminado), UPDATE (contrasena)
--     (app_web no debe aparecer aquí con contrasena).
SELECT cp.grantee, cp.privilege_type, cp.column_name
FROM   information_schema.column_privileges cp
WHERE  cp.table_schema = 'public'
  AND  cp.table_name   = 'usuario'
  AND  cp.grantee IN ('rol_auth', 'rol_auth_reset', 'app_web')
ORDER  BY cp.grantee, cp.privilege_type, cp.column_name;


-- ============================================================
-- QUÉ DEJA ESTE SCRIPT (resumen)
-- ------------------------------------------------------------
-- - pgcrypto instalada SOLO en foodstore_tp_u5.
-- - rol_auth (NOLOGIN)        -> owner de fn_autenticar (solo SELECT).
-- - rol_auth_reset (NOLOGIN)  -> owner de fn_resetear_password
--                                (SELECT mail/eliminado + UPDATE
--                                 contrasena).
-- - fn_autenticar SECURITY DEFINER: hashes crypt, ignora eliminados,
--   valida el formato del hash antes de crypt, devuelve id_usuario |
--   NULL, emite evento LOG sin datos sensibles.
-- - fn_resetear_password SECURITY DEFINER: rehash, sin GRANT a roles
--   de aplicación.
-- - fn_autenticar: EXECUTE SOLO para app_web; PUBLIC revocado; sin
--   ventana pública (pasos agrupados en una transacción).
--
-- CONSECUENCIA DECLARADA: como las contraseñas existentes están en
-- texto plano, los usuarios ya cargados NO podrán autenticarse hasta
-- que sus contraseñas se rehasheen con fn_resetear_password. Es
-- intencional (no se compara texto plano) y debe quedar como hallazgo
-- en el informe.
--
-- LO QUE NO HACE: no migra ni muestra contraseñas existentes, no crea
-- logins, no otorga membresías y no deja datos modificados.
-- ============================================================
