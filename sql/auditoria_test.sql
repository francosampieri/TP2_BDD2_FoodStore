-- ============================================================
-- AUDITORÍA — TP Unidad 5, Parte B
-- Base objetivo: foodstore_tp_u5 (PostgreSQL 17).
--
-- Contexto ya activo (NO se modifica aquí):
--   log_connections = on
--   log_disconnections = on
--   log_statement = mod
--   logging_collector = on  (las líneas van al archivo de log)
--
-- Este script NO contiene ALTER SYSTEM, NO cambia configuración de
-- forma persistente, NO incluye contraseñas y NO commitea datos:
--   - El BLOQUE 1 hace solo consultas de lectura.
--   - El BLOQUE 2 modifica datos de forma TEMPORAL (INSERT + UPDATE)
--     dentro de una transacción que termina en ROLLBACK: no queda
--     ninguna fila.
--   - El BLOQUE 3 abre otra transacción con SET LOCAL y ROLLBACK
--     (no deja 'all' activo).
--   - El BLOQUE 4 es solo comentario: describe una acción manual en
--     la GUI de DBeaver, no ejecuta SQL.
--
-- Ejecutar bloque por bloque en DBeaver, como el superusuario con el
-- que ya está configurado el logging.
-- ============================================================


-- ============================================================
-- BLOQUE 1 — IDENTIFICAR BASE, USUARIO, PID Y ARCHIVO DE LOG
-- Solo lectura. Cuanto antes se anoten estos datos, más fácil es
-- ubicar después las líneas propias dentro del log.
-- ============================================================

-- 1.1 Identidad de la sesión y del servidor.
SELECT current_database()      AS base,
       current_user            AS usuario_actual,
       session_user            AS usuario_sesion,
       pg_backend_pid()        AS pid,
       inet_client_addr()      AS ip_cliente,
       inet_server_addr()      AS ip_servidor,
       inet_server_port()      AS puerto_servidor,
       now()                   AS momento;

-- 1.2 Archivo de log en uso por el collector.
-- pg_current_logfile() devuelve la RUTA del archivo actual y YA incluye
-- log_directory: no hay que anteponerlo otra vez. En instalaciones con
-- csvlog el sufijo puede ser .csv. (Función restringida a superusuarios
-- y roles con pg_monitor.)
SELECT pg_current_logfile()    AS archivo_log_actual;

-- 1.3 Ubicación y destino del log (solo lectura).
SHOW log_directory;
SHOW log_filename;
SHOW log_destination;

-- 1.4 Confirmación de la configuración de auditoría vigente (solo lectura).
SELECT name, setting
FROM   pg_settings
WHERE  name IN ('logging_collector',
                'log_statement',
                'log_connections',
                'log_disconnections',
                'log_directory',
                'log_filename',
                'log_destination')
ORDER  BY name;

-- Anotar: base, usuario, PID y archivo de log. Ese PID es el que
-- prefija las líneas de esta sesión en el archivo (formato típico:
-- "2026-... [PID] ... LOG:  statement: ...").


-- ============================================================
-- BLOQUE 2 — DML CONTROLADO CON log_statement = mod
-- INSERT + UPDATE de una categoría temporal, dentro de una
-- transacción que se cierra con ROLLBACK.
--
-- Clave: las sentencias deben enviarse como TOP-LEVEL (no dentro de
-- un DO block ni de una función), porque log_statement registra las
-- sentencias que recibe el cliente; lo ejecutado dentro de un bloque
-- PL/pgSQL no se registra por separado.
--
-- Nombre distinguible y único: TP_U5_AUD_...
-- ============================================================

BEGIN;

INSERT INTO categoria (nombre_categoria, descripcion_categoria)
VALUES ('TP_U5_AUD_categoria_tmp',
        'Fila temporal de prueba de auditoria (se revierte)');

UPDATE categoria
SET    descripcion_categoria = 'TP_U5_AUD_actualizada'
WHERE  nombre_categoria = 'TP_U5_AUD_categoria_tmp';

ROLLBACK;

-- Verificación de que NO quedó ningún dato (debe devolver 0).
SELECT count(*) AS filas_tp_u5_aud
FROM   categoria
WHERE  nombre_categoria LIKE 'TP_U5_AUD_%';


-- ============================================================
-- BLOQUE 3 — OBSERVAR UN SELECT CON log_statement='all' TEMPORAL
-- Bajo log_statement=mod los SELECT no se registran. Para ver un
-- SELECT en el log sin dejar 'all' activo de forma permanente se usa
-- SET LOCAL, que solo afecta a la transacción actual y se revierte
-- automáticamente al terminar (COMMIT o ROLLBACK).
--
-- NOTA: log_statement es un GUC de contexto superuser; este bloque
-- debe ejecutarse como el superusuario con el que se configuró el
-- logging. No requiere editar ningún archivo ni reiniciar el motor.
-- ============================================================

BEGIN;

-- 'all' rige solo hasta el final de esta transacción.
SET LOCAL log_statement = 'all';

-- Consulta inocua del catálogo: su texto debe aparecer en el log.
SELECT id_categoria, nombre_categoria
FROM   categoria
ORDER  BY id_categoria;

-- ROLLBACK revierte también el SET LOCAL: log_statement vuelve a 'mod'
-- y no queda ningún cambio persistente.
ROLLBACK;

-- Comprobación opcional (solo lectura): tras el ROLLBACK el valor vigente
-- debe seguir siendo 'mod'.
SHOW log_statement;


-- ============================================================
-- BLOQUE 4 — (SOLO COMENTARIO) UN LOGIN FALLIDO CONTROLADO
-- No ejecutar aquí: es una acción manual en la GUI de DBeaver.
--
-- Objetivo: provocar EXACTAMENTE UN login fallido y verlo en el log,
-- usando el rol app_web, que todavía NO tiene contraseña.
--
-- Pasos:
--   1. En DBeaver: Database > New Database Connection (o duplicar la
--      conexión a foodstore_tp_u5).
--   2. Configurar:
--        Host / Port / Database: los mismos de foodstore_tp_u5.
--        User: app_web
--        Password: DEJAR VACÍO (no escribir ninguna contraseña real;
--                  tampoco se pide una).
--   3. Pulsar "Test Connection" / "Connect" UNA sola vez.
--   4. Resultado esperado: el intento falla con
--        FATAL:  password authentication failed for user "app_web"
--      (bajo métodos de autenticación por contraseña, que es el caso
--       habitual en DBeaver).
--
-- Aclaraciones:
--   - NO se define ni se solicita una contraseña real en ningún
--     momento; app_web tiene PASSWORD NULL, así que la autenticación
--     por contraseña falla por definición.
--   - Hacer UN único intento: cada reintento agrega líneas nuevas al
--     log y complica la lectura del caso.
--   - Si pg_hba.conf tuviera un método sin contraseña (trust/peer)
--     para esa conexión, el login podría tener éxito y no habría
--     fallo que registrar; cambiar pg_hba queda fuera del alcance
--     de este TP.
--   - Cerrar la conexión fallida para no dejar intentos repetidos.
-- ============================================================


-- ============================================================
-- QUÉ SE ESPERA VER EN EL LOG
-- ------------------------------------------------------------
-- Prefijo de cada línea: fecha/hora y PID de la sesión
-- (el PID anotado en el BLOQUE 1).
--
-- BLOQUE 1: bajo log_statement=mod los SELECT no se registran, por lo
--   que las consultas de identificación normalmente NO aparecen. Sí
--   puede haber líneas de conexión (log_connections = on):
--     LOG:  connection received: host=... port=...
--     LOG:  connection authorized: user=... database=foodstore_tp_u5
--
-- BLOQUE 2 (esto es lo central de la Parte B):
--     LOG:  statement: BEGIN
--     LOG:  statement: INSERT INTO categoria (nombre_categoria, descripcion_categoria) VALUES (...)
--     LOG:  statement: UPDATE categoria SET descripcion_categoria = '...' WHERE nombre_categoria = '...'
--     LOG:  statement: ROLLBACK
--   Las sentencias de control transaccional (BEGIN/ROLLBACK) pueden
--   figurar o no según la versión; el INSERT y el UPDATE sí se
--   registran bajo 'mod'. Como los valores son literales (no
--   parámetros), el texto queda completo en el log.
--
-- BLOQUE 3: con SET LOCAL log_statement='all', el SELECT se registra:
--     LOG:  statement: SELECT id_categoria, nombre_categoria FROM categoria ORDER BY id_categoria
--   y, tras el ROLLBACK, futuras sentencias de esa sesión vuelven a
--   regirse por 'mod'. El propio SET LOCAL puede no aparecer (bajo
--   'mod' no se clasifica como DML/DDL).
--
-- BLOQUE 4 (acción manual):
--     LOG:  connection received: host=... port=...   (si log_connections = on)
--     FATAL:  password authentication failed for user "app_web"
-- ============================================================


-- ============================================================
-- QUÉ **NO** PRUEBA EL LOG
-- ------------------------------------------------------------
-- - Bajo log_statement=mod no se registran los SELECT: la lectura del
--   catálogo no queda auditada salvo que se suba el nivel (BLOQUE 3).
-- - SÍ puede incluir los VALORES de los parámetros del protocolo
--   extendido (bind): bajo log_statement, al recibirse un mensaje
--   Execute se registran la sentencia y los valores de sus parámetros.
--   log_parameter_max_length controla cuántos bytes se muestran y su
--   valor por defecto (-1) los registra completos. Por eso el log puede
--   contener datos personales e incluso credenciales: refuerza la
--   necesidad de revisarlo y anonimizarlo antes de compartirlo.
-- - No prueba intención ni autorización de negocio: registra el texto
--   de la sentencia y su sesión, no la semántica ni quién "debía" hacerlo.
-- - No prueba persistencia: el INSERT/UPDATE del BLOQUE 2 queda
--   registrado aunque el ROLLBACK lo haya revertido. El log muestra el
--   intento, no el efecto final.
-- - No es prueba de cumplimiento por sí solo: el log vive en el sistema
--   operativo, puede editarse o borrarse, y su valor probatorio depende
--   de la protección del host y de la política de retención.
-- - Es de alcance servidor: todas las sesiones y bases comparten el
--   mismo archivo, no está separado por aplicación ni por usuario.
-- - Las marcas de tiempo usan la zona horaria del servidor.
-- ============================================================


-- ============================================================
-- ANTES DE SUBIR O COMPARTIR EL ARCHIVO DE LOG
-- ------------------------------------------------------------
-- El archivo de log es EVIDENCIA SENSIBLE. Revisarlo y ANONIMIZARLO
-- antes de adjuntarlo en el informe/TP o de compartirlo:
--   - usuarios y roles, nombres reales, correos (mail) y cualquier dato
--     personal que aparezca en sentencias registradas;
--   - direcciones IP/host de cliente y servidor, puertos, rutas y
--     nombres de máquina;
--   - cualquier credencial o cadena de conexión que hubiera quedado.
-- Recortar solo las líneas del caso (el PID del BLOQUE 1 ayuda a
-- aislarlas) y reemplazar los datos personales por marcadores antes de
-- publicar. No subir el log sin anonimizar.
-- ============================================================
