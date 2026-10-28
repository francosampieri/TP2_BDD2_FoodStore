-- ============================================================
-- health_check.sql — Chequeo de salud FoodStore (Unidad 6)
-- Base objetivo: foodstore (PostgreSQL 17)
-- 
-- Controles mínimos según SPEC_U6:
-- 1) Tamaño de la base
-- 2) Conexiones (activos / totales por estado)
-- 3) Actividad / consultas activas
-- 4) Estado de tablas (tuplas vivas/muertas, autovacuum/ANALYZE)
--
-- Adaptado al esquema real: se usa la tabla USUARIO (no CLIENTE).
-- Solo lectura; sin modificaciones.
-- ============================================================

-- Fecha/hora de chequeo
SELECT now() AS fecha_chequeo;

-- Estadísticas globales de la base (pg_stat_database)
SELECT
  datname AS base,
  numbackends AS conexiones_activas_actuales,
  xact_commit  AS transacciones_commit,
  xact_rollback AS transacciones_rollback
FROM pg_stat_database
WHERE datname = 'foodstore';

-- ============================================================
-- 1) TAMAÑO DE LA BASE
-- ============================================================
SELECT
  datname AS base,
  pg_size_pretty(pg_database_size(datname)) AS tamano_pretty,
  pg_database_size(datname) AS tamano_bytes
FROM pg_database
WHERE datname = current_database();

-- Tamaño por esquema (visión rápida)
SELECT
  schemaname,
  pg_size_pretty(SUM(pg_total_relation_size(schemaname||'.'||tablename))::bigint) AS tamano_total_pretty
FROM pg_tables
WHERE schemaname IN ('public')
GROUP BY schemaname;

-- Tamaño por tabla (top relevantes)
SELECT
  schemaname,
  relname AS tabla,
  pg_size_pretty(pg_total_relation_size(relid)) AS tamano_total_pretty,
  pg_total_relation_size(relid) AS tamano_total_bytes
FROM pg_catalog.pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 15;

-- ============================================================
-- 2) CONEXIONES
-- ============================================================
SELECT
  state,
  count(*) AS cantidad
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND datname = 'foodstore'
GROUP BY state
ORDER BY state;

SELECT
  usename AS usuario,
  application_name,
  client_addr,
  state,
  count(*) AS cantidad
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND datname = 'foodstore'
GROUP BY usename, application_name, client_addr, state
ORDER BY cantidad DESC;

-- ============================================================
-- 3) ACTIVIDAD / CONSULTAS ACTIVAS
-- ============================================================
SELECT
  pid,
  usename,
  application_name,
  client_addr,
  state,
  now() - query_start AS duracion,
  left(query, 100) AS query_preview
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND datname = 'foodstore'
  AND state <> 'idle'
ORDER BY duracion DESC;

-- Consultas activas largas (umbral orientativo)
SELECT
  pid,
  usename,
  state,
  now() - xact_start AS duracion_transaccion,
  now() - query_start AS duracion_query,
  left(query, 120) AS query_preview
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND datname = 'foodstore'
  AND (now() - query_start > interval '30 seconds' OR now() - xact_start > interval '60 seconds')
ORDER BY COALESCE(xact_start, query_start);

-- ============================================================
-- 4) ESTADO DE TABLAS (tuplas vivas/muertas, autovacuum/ANALYZE)
--    Adaptado: usar tabla 'usuario' (no 'cliente')
-- ============================================================
SELECT
  schemaname,
  relname AS tabla,
  n_live_tup AS tuplas_vivas,
  n_dead_tup AS tuplas_muertas,
  CASE
    WHEN n_live_tup > 0 THEN round((n_dead_tup::numeric / n_live_tup::numeric) * 100, 2)
    ELSE 0
  END AS porcentaje_muertas,
  last_autovacuum,
  last_vacuum,
  last_analyze,
  last_autoanalyze,
  autovacuum_count,
  vacuum_count,
  analyze_count,
  autoanalyze_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC, porcentaje_muertas DESC;

-- Verificación rápida de conteos clave (sanidad)
SELECT 'categoria' AS tabla, count(*) AS total FROM categoria
UNION ALL
SELECT 'usuario', count(*) FROM usuario
UNION ALL
SELECT 'producto', count(*) FROM producto
UNION ALL
SELECT 'pedido', count(*) FROM pedido
UNION ALL
SELECT 'detalle_pedido', count(*) FROM detalle_pedido;
