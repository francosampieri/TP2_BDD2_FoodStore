-- ============================================================
-- COMPETENCIA DE OPTIMIZACIÓN — TP3 FoodStore (Parte 5)
--
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17).
-- Consulta común de la cátedra adaptada al esquema FoodStore.
--
-- Estrategia:
--   La consulta filtra producto por id_categoria, disponible = TRUE,
--   eliminado = FALSE y rango de precio, ordenando por precio DESC.
--   Sin índice específico, el planner usaba idx_producto_id_categoria
--   (Bitmap Heap Scan) trayendo ~7.147 filas de la categoría y
--   descartando ~3.980 por el resto de los filtros.
--   El índice aceptado combina la categoría con el precio y aplica de
--   antemano los filtros de vigencia, dejando el heap con solo las
--   filas del resultado y evitando "Rows Removed by Filter".
--
-- RESULTADOS REALES (EXPLAIN ANALYZE real, post ANALYZE):
--   Antes  : nodo raíz Sort (costo 1225.98..1234.01); Bitmap Heap Scan
--            sobre producto con idx_producto_id_categoria; 7.147 filas
--            traídas y ~3.980 descartadas por disponible/eliminado/rango
--            de precio; Heap Blocks exact=810.
--            Execution Time: 93.394 ms.
--   Después: nodo raíz Sort (costo 1140.54..1148.41); Bitmap Index Scan
--            usando idx_producto_cat_precio_disp_vig; Recheck Cond cubre
--            categoría, rango de precio, disponible y no eliminado;
--            devuelve 3.167 filas, sin "Rows Removed by Filter";
--            Heap Blocks exact=738; el Sort permanece.
--            Execution Time: 10.855 ms.
--   Mejora aproximada: 8.6x respecto de 93.394 ms.
--   El Sort se mantiene en ambos planes: el acceso por índice mejoró
--   significativamente, pero el orden final por precio DESC sigue
--   requiriendo ordenar el resultado.
--   El índice fue creado definitivamente y se ejecutó ANALYZE producto.
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

-- Índice aceptado (único que superó la validación por Execution Time)
CREATE INDEX idx_producto_cat_precio_disp_vig
ON producto (id_categoria, precio DESC)
WHERE disponible = TRUE
  AND eliminado = FALSE;