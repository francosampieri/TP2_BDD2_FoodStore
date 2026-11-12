-- cargar_snapshot.sql
-- Ejecutar en SQLite DESPUÉS de:
--   1) DELETE FROM snapshot_servidor;
--   2) .import --csv --skip 1 movil/servidor_snapshot.csv snapshot_servidor
-- (Orden válido según tasks.md; no importar antes de vaciar.)
--
-- Actualiza producto_cache mediante UPSERT para conservar referencias de item_borrador.
-- NOTA: item_borrador referencia producto_cache (FK sin ON DELETE CASCADE);
-- por eso NO se borra/reinserta producto_cache, se usa ON CONFLICT DO UPDATE.
-- Se agrega WHERE 1 antes de ON CONFLICT para evitar ambigüedad del parser SQLite.

PRAGMA foreign_keys = ON;

INSERT INTO producto_cache (
    producto_id,
    nombre,
    precio_centavos,
    stock_visto,
    disponible_visto,
    eliminado,
    capturado_en
)
SELECT
    producto_id,
    nombre,
    precio_centavos,
    stock,
    CASE disponible WHEN 't' THEN 1 ELSE 0 END,
    CASE eliminado  WHEN 't' THEN 1 ELSE 0 END,
    capturado_en
FROM snapshot_servidor
WHERE 1
ON CONFLICT(producto_id) DO UPDATE SET
    nombre           = excluded.nombre,
    precio_centavos  = excluded.precio_centavos,
    stock_visto      = excluded.stock_visto,
    disponible_visto = excluded.disponible_visto,
    eliminado        = excluded.eliminado,
    capturado_en     = excluded.capturado_en;

-- Verificación rápida
SELECT producto_id, nombre, precio_centavos, stock_visto, disponible_visto, eliminado
FROM producto_cache
ORDER BY producto_id;
