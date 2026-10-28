-- ============================================================
-- maintenance.sql — Revisión de mantenimiento FoodStore (Unidad 6)
--
-- OBJETIVO: MOSTRAR PRIMERO LAS METRICAS Y EJECUTAR UNA ACCION MANUAL
--           PUNTUAL JUSTIFICADA. No usar como tarea programada.
--
-- Base objetivo: foodstore (PostgreSQL 17)
-- Esquema real: tabla 'usuario' (adaptado, no 'cliente')
--
-- ATENCION: el bloque 4 ejecuta ANALYZE public.pedido. Correr este archivo
-- manualmente en DBeaver, conectado a foodstore y con autocommit activo.
-- ANALYZE actualiza estadisticas; no modifica las filas de pedidos.
-- ============================================================

-- 1) MÉTRICAS QUE JUSTIFICAN ACCIÓN (PRIMERO)
-- Tuplas vivas/muertas e historial de autovacuum/ANALYZE.
-- IMPORTANTE: n_dead_tup NO es una medida directa de "bloat" (espacio
--   ocupado). Es un indicador orientativo de tuplas no visibles que
--   pueden requerir VACUUM. Cualquier decisión de acción debe basarse
--   en las métricas reales observadas, no solo en estos valores.
SELECT
  schemaname,
  relname AS tabla,
  n_live_tup AS tuplas_vivas,
  n_dead_tup AS tuplas_muertas,
  CASE
    WHEN n_live_tup > 0 THEN round((n_dead_tup::numeric / n_live_tup::numeric) * 100, 2)
    ELSE 0
  END AS pct_muertas_orientativo,
  last_autovacuum,
  last_vacuum,
  last_autoanalyze,
  last_analyze,
  autovacuum_count,
  autoanalyze_count,
  vacuum_count,
  analyze_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC, pct_muertas_orientativo DESC;

-- Tablas con mayor acumulación (orientativo, NO equivale a bloat)
SELECT
  schemaname,
  relname AS tabla,
  n_dead_tup AS tuplas_muertas,
  CASE
    WHEN n_live_tup > 0 THEN round((n_dead_tup::numeric / n_live_tup::numeric) * 100, 2)
    ELSE 0
  END AS pct_muertas_orientativo,
  last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
   OR (n_live_tup > 0 AND (n_dead_tup::numeric / n_live_tup::numeric) > 0.10)
ORDER BY n_dead_tup DESC;

-- 2) ESTADO DE ÍNDICES (uso/orientativo)
SELECT
  schemaname,
  relname AS tabla,
  indexrelname AS indice,
  idx_scan AS escaneos_indice,
  idx_tup_read AS tuplas_leidas_via_indice,
  idx_tup_fetch AS tuplas_obtenidas_via_indice,
  pg_size_pretty(pg_relation_size(indexrelid)) AS tamano_indice
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- 3) BLOQUEOS / TRANSACCIONES ABIERTAS (revisar antes de actuar)
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
ORDER BY COALESCE(xact_start, query_start);

-- 4) ACCION MANUAL JUSTIFICADA
--
-- GUÍA (orientativa, decidir caso por caso después de observar métricas
-- reales):
-- - VACUUM (normal): puede ayudar a marcar tuplas muertas como reutilizables;
--   NO implica recuperar espacio a nivel de archivo en todos los casos.
-- - ANALYZE: actualizar estadísticas para el planificador.
-- - VACUUM FULL: REESCRIBE la tabla y los índices, bloquea la tabla, requiere
--   espacio extra, NO es rutinario. NO se ejecuta aquí.
-- - REINDEX: solo si hay evidencia concreta que lo justifique.
--
-- Observacion del 2026-10-28: COUNT(*) sobre pedido = 21, mientras la
-- consulta de pg_stat_user_tables devolvio 0/NULL para las estimaciones y
-- fechas de mantenimiento. Actualizamos las estadisticas de esta tabla
-- para que el planificador cuente con datos actuales. No hay evidencia
-- que justifique VACUUM o VACUUM FULL.
ANALYZE public.pedido;

-- Comprobar el resultado en una consulta nueva despues del autocommit.
SELECT relname AS tabla, n_live_tup, n_dead_tup, last_analyze, analyze_count
FROM pg_stat_user_tables
WHERE relid = 'public.pedido'::regclass;
