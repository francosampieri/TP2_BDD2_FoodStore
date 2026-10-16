-- ============================================================
-- SIMULACRO DE INCIDENTE DE ACCESO INDEBIDO — TP Unidad 5, Parte C
--
-- Base objetivo: foodstore_tp_u5 (PostgreSQL 17), EXCLUSIVAMENTE.
-- Prerequisito: haber ejecutado sql/autenticacion_u5.sql en esta base
--   (pgcrypto instalada, fn_autenticar creada y con EXECUTE para
--   app_web). Este script NO instala nada ni crea roles.
--
-- Se reproduce la secuencia pedida por la consigna:
--   (1) varios intentos fallidos contra fn_autenticar,
--   (2) un inicio de sesión exitoso,
--   (3) una lectura masiva de usuario (solo columnas que app_web puede
--       leer: id_usuario y eliminado),
--   (4) un intento de escalamiento: GRANT admin_datos TO app_web.
--
-- MODELO DE EJECUCIÓN (leer antes de correr):
--   - La conexión SIGUE autenticada como postgres (superusuario).
--     El cambio de rol se hace con SET LOCAL ROLE app_web: es una
--     SIMULACIÓN DE PERMISOS (postgres "actúa como" app_web dentro de
--     la transacción), NO un login real de app_web.
--   - Todo ocurre en UNA transacción que termina en ROLLBACK: no deja
--     el usuario sintético, ni la membresía, ni cambios de datos.
--   - El usuario sintético y su contraseña son 100% ficticios.
--   - El usuario sintético se inserta ANTES de activar
--     log_statement='all', para que el foco del log sean los intentos
--     de autenticación y la lectura (no el alta de prueba).
--   - El prefijo de log se cambia de forma TEMPORAL con ALTER SYSTEM
--     (nivel SERVIDOR: afecta a TODAS las bases, no solo a
--     foodstore_tp_u5) en el BLOQUE 0.9, y se RESTAURA con otro
--     ALTER SYSTEM en el BLOQUE 9. NO se usa SET LOCAL: log_line_prefix
--     es un parámetro de tipo sighup y SET LOCAL falla dentro de una
--     transacción. La restauración es OBLIGATORIA, incluso si el
--     simulacro se interrumpe por un error.
--
-- ADVERTENCIA: NO enviar el log bruto a ninguna IA. Las sentencias
-- registradas bajo log_statement='all' pueden incluir la contraseña
-- sintética y datos de usuario; hay que ANONIMIZAR antes de compartir
-- (ver la sección final).
--
-- Ejecutar bloque por bloque, EN ORDEN y EN LA MISMA SESIÓN de
-- DBeaver (la transacción abarca los BLOQUES 1 a 7). No ejecutar todo
-- de una sola vez: el resultado del BLOQUE 6 define pasos manuales.
-- ============================================================


-- ============================================================
-- BLOQUE 0 — PRECHECKS (solo lectura)
-- Confirmar cada punto antes de simular.
-- ============================================================

-- 0.1 Abortar si no estamos en foodstore_tp_u5.
DO $$
BEGIN
    IF current_database() <> 'foodstore_tp_u5' THEN
        RAISE EXCEPTION
            'Simulacro abortado: conectar a foodstore_tp_u5 (actual: %)',
            current_database();
    END IF;
END
$$;

-- 0.2 Identidad de la sesión: se espera usuario_sesion = postgres
--     (superusuario). Es necesario para SET LOCAL ROLE y para
--     SET LOCAL log_statement.
SELECT current_database() AS base,
       session_user       AS usuario_sesion,
       current_user       AS usuario_actual,
       pg_backend_pid()   AS pid_sesion;

-- 0.3 pgcrypto instalada (esperado: una fila, 1.3).
SELECT e.extname, e.extversion
FROM   pg_extension e
WHERE  e.extname = 'pgcrypto';

-- 0.4 fn_autenticar existe, es SECURITY DEFINER y la posee rol_auth.
--    Esperado: prosecdef = true, propietario = rol_auth.
SELECT p.proname,
       p.prosecdef                 AS security_definer,
       pg_get_userbyid(p.proowner) AS propietario
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'fn_autenticar';

-- 0.5 app_web puede ejecutar fn_autenticar (esperado: true).
SELECT has_function_privilege('app_web','public.fn_autenticar(text,text)','EXECUTE')
           AS app_web_puede_autenticar;

-- 0.6 app_web NO debe pertenecer a admin_datos (esperado: 0).
SELECT count(*) AS app_web_ya_en_admin_datos
FROM   pg_auth_members m
JOIN   pg_roles r_member ON r_member.oid = m.member
JOIN   pg_roles r_role   ON r_role.oid   = m.roleid
WHERE  r_member.rolname = 'app_web' AND r_role.rolname = 'admin_datos';

-- 0.7 GUC de logging. Se espera log_min_messages = warning (valor por
--     defecto): con ese valor los eventos RAISE LOG de fn_autenticar
--     SÍ se escriben en el log del servidor. Anotar el valor observado.
SHOW log_min_messages;
SHOW log_statement;

-- 0.8 Prefijo de línea de log. IMPORTANTE: en la Parte B el prefijo
--     quedó restaurado a '%t ' (SOLO fecha/hora, SIN PID ni usuario).
--     Con ese prefijo las líneas del log NO permiten identificar la
--     sesión ni el rol efectivo, que es lo que este simulacro necesita
--     mostrar. Anotar el valor observado: es el valor al que hay que
--     volver al final. El BLOQUE 0.9 fija un prefijo temporal con
--     fecha + PID + usuario + base. No se afirma que el PID aparezca
--     si no se configuró.
SHOW log_line_prefix;


-- ============================================================
-- BLOQUE 0.9 — PREFIJO DE LOG TEMPORAL (ALTER SYSTEM, NIVEL SERVIDOR)
-- ATENCIÓN: este cambio NO es local a foodstore_tp_u5. ALTER SYSTEM
--          modifica la configuración del SERVIDOR y afecta el formato
--          de log de TODAS las bases hasta que se restaure (BLOQUE 9).
-- MOTIVO: log_line_prefix es un parámetro de tipo sighup; NO puede
--         fijarse con SET LOCAL dentro de una transacción (habría que
--         usar SET de sesión, que no se revierte con el ROLLBACK). Por
--         eso se usa ALTER SYSTEM + pg_reload_conf() y se restaura de
--         forma explícita al final.
-- REQUIERE: superusuario (postgres), que es el usuario de esta sesión.
-- IDEMPOTENTE PARA LA PRUEBA: si ya se ejecutó, volver a ejecutarlo
--         deja el mismo prefijo. NO dejar sin restaurar.
-- ============================================================

-- 0.9.1 Fijar el prefijo temporal: fecha (%m), PID (%p), usuario
--       (%u) y base (%d).
ALTER SYSTEM SET log_line_prefix = '%m [%p] %u@%d ';

-- 0.9.2 Recargar la configuración para que el cambio tome efecto
--       (ALTER SYSTEM solo escribe postgresql.auto.conf).
SELECT pg_reload_conf();

-- 0.9.3 Verificar (esperado: '%m [%p] %u@%d ').
SHOW log_line_prefix;
-- Anotar lo observado: ____________________________________________


-- ============================================================
-- BLOQUE 1 — ABRIR TRANSACCIÓN + ALTA DEL USUARIO SINTÉTICO
-- Todo lo que sigue hasta el BLOQUE 7 queda SIN confirmar (ROLLBACK).
--
-- Nombre de mail reservado (.invalid) y contraseña ficticia.
-- La contraseña se almacena YA HASHEADA con crypt + gen_salt('bf'):
-- nunca se guarda en texto plano.
-- ============================================================

BEGIN;

-- Se apaga el registro de sentencias ANTES del alta: así el INSERT de
-- prueba no ensucia el log con la contraseña sintética.
SET LOCAL log_statement = 'none';

INSERT INTO public.usuario (nombre_usuario, apellido, mail, contrasena, rol)
VALUES ('Sintetico',
        'Simulacro',
        'u5.simulacro@synth.invalid',
        public.crypt('SynthU5_pass!', public.gen_salt('bf')),
        'USUARIO')
RETURNING id_usuario AS usuario_sintetico_id;

-- Anotar el id devuelto (usuario_sintetico_id).
-- Observado: ______________________________________________________


-- ============================================================
-- BLOQUE 2 — ACTIVAR LOG 'all' SOLO EN ESTA TRANSACCIÓN Y CAMBIAR DE ROL
--  - SET LOCAL log_statement='all': registra los SELECT de esta
--    transacción y se revierte automáticamente con el ROLLBACK final.
--    NO se activa 'all' de forma permanente para toda la base.
--  - El PREFIJO de log NO se toca aquí: ya quedó fijado a nivel
--    servidor en el BLOQUE 0.9 (ALTER SYSTEM) y se restaura en el
--    BLOQUE 9. NO se usa SET LOCAL log_line_prefix (parámetro sighup).
--  - SET LOCAL ROLE app_web: SIMULACIÓN DE PERMISOS, no login real.
--    Debe hacerse DESPUÉS de fijar log_statement, porque app_web no
--    puede cambiar ese GUC.
-- ============================================================

SET LOCAL log_statement = 'all';

SET LOCAL ROLE app_web;

-- Confirmar el rol efectivo (esperado: current_user = app_web,
-- session_user sigue siendo postgres).
SELECT current_user AS usuario_efectivo, session_user AS usuario_sesion;


-- ============================================================
-- BLOQUE 3 — VARIOS INTENTOS FALLIDOS CONTRA fn_autenticar
-- Ejecutados como rol efectivo app_web.
-- El log de un SELECT NO muestra el valor devuelto: la función emite
-- el evento RAISE LOG 'fn_autenticar: intento resultado=FALLO'.
-- ============================================================

-- 3.1 Contraseña incorrecta (esperado: NULL).
SELECT public.fn_autenticar('u5.simulacro@synth.invalid', 'intento_fallido_1')
           AS intento_1_fallido;

-- 3.2 Contraseña incorrecta distinta (esperado: NULL).
SELECT public.fn_autenticar('u5.simulacro@synth.invalid', 'intento_fallido_2')
           AS intento_2_fallido;

-- 3.3 Mail inexistente (esperado: NULL).
SELECT public.fn_autenticar('no.existe@synth.invalid', 'intento_fallido_3')
           AS intento_3_fallido;

-- Observado: ______________________________________________________


-- ============================================================
-- BLOQUE 4 — UN INTENTO EXITOSO
-- Con la contraseña sintética correcta (esperado: el id del usuario
-- sintético anotado en el BLOQUE 1).
-- ============================================================

SELECT public.fn_autenticar('u5.simulacro@synth.invalid', 'SynthU5_pass!')
           AS intento_exitoso;

-- Observado: ______________________________________________________
-- El log debe mostrar: RAISE LOG 'fn_autenticar: intento resultado=OK'.


-- ============================================================
-- BLOQUE 5 — LECTURA MASIVA DE usuario (SIN LIMIT)
-- Como app_web solo puede leer id_usuario y eliminado, la lectura
-- masiva se limita EXACTAMENTE a esas columnas. Leer cualquier otra
-- columna (mail, contrasena, ...) daría "permission denied".
-- ============================================================

SELECT id_usuario, eliminado
FROM   public.usuario;
-- Sin LIMIT: es la lectura masiva de la tabla.

-- Observado (nº de filas): ________________________________________


-- ============================================================
-- BLOQUE 6 — INTENTO DE ESCALAMIENTO (con SAVEPOINT)
-- Como rol efectivo app_web, intentar obtener membresía en admin_datos.
-- RESULTADO ESPERADO: ERROR "permission denied to grant role"
--   (app_web no es superusuario ni tiene ADMIN OPTION sobre admin_datos).
-- El SAVEPOINT permite recuperar la transacción sin abortarla entera.
-- ============================================================

SAVEPOINT sp_intento_grant;

GRANT admin_datos TO app_web;

-- ------------------------------------------------------------------
-- PASOS MANUALES SEGÚN EL RESULTADO DE ESTE BLOQUE (leer antes de seguir):
--
-- (A) SI FALLA (resultado ESPERADO):
--       El escalamiento está contenido -> es un aspecto correcto del
--       diseño. Continuar así, en este orden:
--         1) ROLLBACK TO SAVEPOINT sp_intento_grant;   -- descarta el intento fallido
--         2) ir al BLOQUE 7 y ejecutar ROLLBACK;        -- cierra la transacción
--
-- (B) SI TIENE ÉXITO (resultado INESPERADO = DEFECTO DE PERMISOS):
--         1) ejecutar INMEDIATAMENTE ROLLBACK;          -- no confirmar nunca
--         2) DETENER el simulacro (no seguir con los BLOQUES 7/8).
--         3) IR AL BLOQUE 9 y RESTAURAR el prefijo (ALTER SYSTEM RESET
--            + pg_reload_conf): el cambio del BLOQUE 0.9 sigue activo
--            a nivel servidor.
--         4) Documentarlo como HALLAZGO/DEFECTO de la Parte A en
--            informe_incidente.md (app_web pudo escalar a admin_datos).
--
-- EN AMBOS CAMINOS, ANTE CUALQUIER ERROR O INTERRUPCIÓN: el prefijo
-- del BLOQUE 0.9 debe restaurarse igualmente con el BLOQUE 9.
--
-- NINGÚN camino usa COMMIT. Ningún camino deja al usuario sintético ni
-- una membresía nueva: (A) descarta el intento y luego revierte todo;
-- (B) revierte todo de inmediato.
-- ------------------------------------------------------------------


-- ============================================================
-- BLOQUE 7 — CIERRE (ROLLBACK GENERAL)
-- Camino (A) esperado: si el BLOQUE 6 falló, primero ejecutar de forma
-- manual  ROLLBACK TO SAVEPOINT sp_intento_grant;  y luego este bloque.
-- Este ROLLBACK revierte: el alta sintética, el SET LOCAL ROLE, el
-- SET LOCAL log_statement y cualquier efecto del intento de GRANT.
-- OJO: NO revierte el prefijo del BLOQUE 0.9 (es un cambio de servidor
-- hecho con ALTER SYSTEM, no una sentencia de la transacción); por eso
-- el prefijo se restaura aparte, en el BLOQUE 9.
-- ============================================================

ROLLBACK;


-- ============================================================
-- BLOQUE 8 — VERIFICACIÓN POSTERIOR (solo lectura, ya sin transacción)
-- Debe ejecutarse como postgres (el ROLLBACK devolvió el rol).
-- ============================================================

-- 8.1 El usuario sintético NO debe existir (esperado: 0).
SELECT count(*) AS usuario_sintetico_restante
FROM   public.usuario
WHERE  mail = 'u5.simulacro@synth.invalid';

-- 8.2 NO debe haberse creado la membresía app_web -> admin_datos
--     (esperado: 0).
SELECT count(*) AS membresia_app_web_admin_datos
FROM   pg_auth_members m
JOIN   pg_roles r_member ON r_member.oid = m.member
JOIN   pg_roles r_role   ON r_role.oid   = m.roleid
WHERE  r_member.rolname = 'app_web' AND r_role.rolname = 'admin_datos';

-- 8.3 El rol efectivo volvió a postgres y log_statement a su valor
--     previo (esperado: log_statement = none|mod, no 'all'). El
--     prefijo NO se verifica aquí: es un cambio de servidor (BLOQUE
--     0.9) que se restaura en el BLOQUE 9.
SELECT current_user AS usuario_efectivo, session_user AS usuario_sesion;
SHOW log_statement;


-- ============================================================
-- BLOQUE 9 — RESTAURACIÓN DEL PREFIJO DE LOG (FUERA DE LA TRANSACCIÓN)
-- OBLIGATORIO. Debe ejecutarse SIEMPRE al terminar el simulacro, haya
-- salido bien o mal. El BLOQUE 0.9 cambió el prefijo a nivel SERVIDOR
-- (ALTER SYSTEM) y el ROLLBACK del BLOQUE 7 NO lo revierte. Si el
-- simulacro se interrumpe por un error antes del BLOQUE 7, volver al
-- ROLLBACK (para limpiar la transacción) y ejecutar igualmente este
-- bloque.
-- IMPORTANTE: como el cambio fue con ALTER SYSTEM, se restaura con
-- ALTER SYSTEM RESET (NO con ALTER DATABASE RESET).
-- ============================================================

-- 9.1 Quitar el valor temporal de postgresql.auto.conf. Al no quedar
--     valor en ALTER SYSTEM, el prefijo vuelve al valor de
--     postgresql.conf (esperado: '%t ').
ALTER SYSTEM RESET log_line_prefix;

-- 9.2 Recargar para que la restauración tome efecto.
SELECT pg_reload_conf();

-- 9.3 Verificación final (esperado: '%t ', el valor anotado en 0.8).
SHOW log_line_prefix;
-- Anotar lo observado: ____________________________________________


-- ============================================================
-- QUÉ SE ESPERA VER EN EL LOG
-- ------------------------------------------------------------
-- Con SET LOCAL log_statement='all' (BLOQUE 2) y el prefijo de
-- servidor del BLOQUE 0.9 (que incluye %p), las sentencias de los
-- BLOQUES 3 a 6 quedan registradas con el PID de la sesión (0.2). Si
-- por algún motivo el prefijo no incluyera %p, aislar las líneas por
-- ventana de tiempo, no por PID.
--   - Los SELECT public.fn_autenticar(...) con sus argumentos.
--   - El SELECT id_usuario, eliminado FROM public.usuario.
--   - El GRANT admin_datos TO app_web con su ERROR si falla.
-- Además, fn_autenticar emite sus propios eventos (sin datos
-- sensibles), visibles con log_min_messages = warning (0.7):
--   - fn_autenticar: intento resultado=FALLO   (tres veces)
--   - fn_autenticar: intento resultado=OK      (una vez)
-- El alta sintética del BLOQUE 1 NO se registra con 'all' (se hizo con
-- log_statement='none').
-- ============================================================


-- ============================================================
-- QUÉ **NO** PRUEBA EL LOG
-- ------------------------------------------------------------
-- - El texto de la sentencia no muestra el VALOR DEVUELTO por
--   fn_autenticar: por eso la función emite su propio evento LOG.
-- - La presencia de una sentencia no prueba su efecto: el alta y los
--   intentos quedan registrados aunque el ROLLBACK los haya revertido.
-- - Bajo log_statement='all' pueden quedar la contraseña SINTÉTICA y
--   datos de usuario en el texto de las sentencias (parámetros bind):
--   es evidencia sensible y debe anonimizarse.
-- - SET LOCAL ROLE app_web NO es un login real: es una suplantación de
--   permisos dentro de una sesión ya autenticada como postgres. El log
--   lo muestra como sentencia, no como autenticación de app_web.
-- ============================================================


-- ============================================================
-- ANTES DE COMPARTIR EL FRAGMENTO (ANONIMIZACIÓN)
-- ------------------------------------------------------------
-- NO enviar el log bruto a ninguna IA. Recortar solo las líneas del
-- caso (si el prefijo incluye %p, el PID de 0.2 ayuda a aislarlas;
-- si es '%t ', aislarlas por ventana de tiempo) y reemplazar por
-- valores sintéticos:
--   - mails, nombres, apellidos, celulares y cualquier dato personal;
--   - la contraseña sintética que aparezca en los argumentos del
--     SELECT -> sustituir por <password_sintetica>;
--   - IP, host, puertos, rutas y nombres de máquina.
-- Mantener la estructura (PID, hora, usuario, sentencia, resultado) para
-- que la reconstrucción sea posible. Guardar el extracto anonimizado en
-- docs/log_simulacro_anonimizado.txt (fuera de este script).
-- ============================================================
