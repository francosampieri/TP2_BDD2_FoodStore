-- ============================================================
-- COMPETENCIA — TP4 FoodStore (Parte 4)
--
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17).
-- Consulta común de la cátedra adaptada al esquema FoodStore.
--
-- Esta consulta reutiliza el índice existente
-- idx_producto_cat_precio_disp_vig, creado y aceptado en el TP3
-- (Parte 5) sobre producto (id_categoria, precio DESC)
-- WHERE disponible = TRUE AND eliminado = FALSE.
--
-- NO se incluye CREATE INDEX ni DDL: el índice ya existe en
-- foodstore_tp3 y su beneficio fue validado con medición real en
-- el TP3 (ver sql/competencia_optimizacion_tp3.sql).
-- ============================================================

-- Consulta común de la cátedra adaptada al esquema FoodStore
SELECT id_producto AS id,
       nombre_producto AS nombre,
       precio,
       stock
FROM producto
WHERE id_categoria = 1
  AND disponible = TRUE
  AND eliminado = FALSE
  AND precio BETWEEN 1000 AND 3000
ORDER BY precio DESC;