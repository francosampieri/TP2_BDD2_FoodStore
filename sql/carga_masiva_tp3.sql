-- ============================================================
-- CARGA MASIVA — TP3 FoodStore
-- Base de ejecución documentada: foodstore_tp3 (PostgreSQL 17)
-- NO incluye CREATE DATABASE. NO modifica foodstore ni foodstore_tp2.
--
-- Tablas temporales (ON COMMIT DROP) capturan los IDs creados.
-- No se asumen ID consecutivos ni se reutilizan CTEs entre sentencias.
-- No se informa total, precio_unitario ni subtotal: los calculan los
-- triggers existentes (trg_subtotal y trg_total_ins).
--
-- FLUJO:
--   1) Este script arranca con BEGIN.
--   2) DML + verificaciones quedan DENTRO de la transacción.
--   3) Al final NO hay COMMIT ni ROLLBACK ejecutable: el usuario elige
--      manualmente en la misma sesión según el resultado de las
--      verificaciones (ver comentarios al final).
--   4) ANALYZE se ejecuta SOLO después del COMMIT (ver comentario final).
-- ============================================================

BEGIN;

-- ============================================================
-- TABLAS TEMPORALES (ON COMMIT DROP)
-- ============================================================

CREATE TEMP TABLE tmp_tp3_productos (id_producto BIGINT PRIMARY KEY) ON COMMIT DROP;
CREATE TEMP TABLE tmp_tp3_usuarios  (id_usuario  BIGINT PRIMARY KEY) ON COMMIT DROP;
CREATE TEMP TABLE tmp_tp3_pedidos   (id_pedido   BIGINT PRIMARY KEY) ON COMMIT DROP;

-- ============================================================
-- 1) PRODUCTOS (>= 50.000) -> tmp_tp3_productos
--    Categorías vigentes mediante lista numerada.
--    Precio entre 500 y 5000; stock entre 0 y 200; disponible TRUE.
-- ============================================================

WITH categorias_numeradas AS (
    SELECT id_categoria,
           ROW_NUMBER() OVER (ORDER BY id_categoria) AS idx_cat,
           count(*) OVER () AS n_cat
    FROM   categoria
    WHERE  eliminado = FALSE
),
generados AS (
    SELECT g.n AS n_seq,
           c.id_categoria
    FROM   generate_series(1, 50000) AS g(n)
    JOIN   categorias_numeradas c
           ON c.idx_cat = ((g.n - 1) % c.n_cat) + 1
),
insertados AS (
    INSERT INTO producto (
        nombre_producto,
        precio,
        descripcion_producto,
        stock,
        disponible,
        id_categoria
    )
    SELECT
        'TP3_Producto_' || g.n_seq,
        500 + ((g.n_seq * 37) % 4501)::numeric(10,2),   -- 500..5000
        'Producto masivo TP3 ' || g.n_seq,
        (g.n_seq * 17) % 201,                            -- 0..200
        TRUE,
        g.id_categoria
    FROM   generados g
    RETURNING id_producto, nombre_producto
)
INSERT INTO tmp_tp3_productos (id_producto)
SELECT id_producto FROM insertados;

-- ============================================================
-- 2) USUARIOS (>= 20.000) -> tmp_tp3_usuarios
--    mail unificado: tp3_usuario_<n>@mail.com
-- ============================================================

WITH insertados AS (
    INSERT INTO usuario (
        nombre_usuario,
        apellido,
        mail,
        celular,
        contrasena,
        rol
    )
    SELECT
        'TP3_Nombre_' || n,
        'TP3_Apellido_' || n,
        'tp3_usuario_' || n || '@mail.com',
        '2619' || lpad((n % 100000000)::text, 8, '0'),
        'tp3_pass_' || n,
        'USUARIO'
    FROM   generate_series(1, 20000) AS g(n)
    RETURNING id_usuario
)
INSERT INTO tmp_tp3_usuarios (id_usuario)
SELECT id_usuario FROM insertados;

-- ============================================================
-- 3) PEDIDOS (>= 200.000) -> tmp_tp3_pedidos
--    Fechas distribuidas en los últimos 365 días.
--    ENUM válidos: estado y forma_pago en mayúsculas sin tildes.
--    total NO se informa (default 0; lo recalcula trg_total_ins).
-- ============================================================

WITH usuarios_numerados AS (
    SELECT id_usuario,
           ROW_NUMBER() OVER (ORDER BY id_usuario) AS idx_usuario
    FROM   tmp_tp3_usuarios
),
insertados AS (
    INSERT INTO pedido (
        fecha,
        estado,
        forma_pago,
        id_usuario
    )
    SELECT
        CURRENT_DATE - ((g.n % 365)::int),               -- últimos 365 días
        (ARRAY['PENDIENTE','CONFIRMADO','TERMINADO'])[(g.n % 3) + 1]::estado_pedido,
        (ARRAY['EFECTIVO','TRANSFERENCIA','TARJETA'])[(g.n % 3) + 1]::forma_pago,
        u.id_usuario
    FROM   generate_series(1, 200000) AS g(n)
    JOIN   usuarios_numerados u ON u.idx_usuario = ((g.n - 1) % 20000) + 1
    RETURNING id_pedido
)
INSERT INTO tmp_tp3_pedidos (id_pedido)
SELECT id_pedido FROM insertados;

-- ============================================================
-- 4) DETALLES (exactamente dos por pedido) ~ 400.000 filas
--    - pedidos numerados en CTE ANTES del CROSS JOIN con k = 1, 2
--    - N (cantidad de productos TP3) calculado una sola vez
--    - indice_producto_destino por aritmética
--    - JOIN contra productos numerados (sin subselect correlacionado)
--    - cantidad = 1 + ((ped_idx + k) % 4) -> 1..4, positiva
--    - precio_unitario / subtotal NO se informan (los completa trg_subtotal)
-- ============================================================

INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad)
WITH pedidos_numerados AS (
    SELECT id_pedido,
           ROW_NUMBER() OVER (ORDER BY id_pedido) AS ped_idx
    FROM   tmp_tp3_pedidos
),
n_productos AS (
    SELECT count(*) AS n FROM tmp_tp3_productos
),
detalles_generados AS (
    SELECT ped.id_pedido,
           k,
           ((ped.ped_idx - 1) * 2 + k - 1) % np.n + 1 AS indice_producto_destino,  -- 1..N
           1 + ((ped.ped_idx + k) % 4) AS cantidad                                 -- 1..4
    FROM   pedidos_numerados ped
    CROSS JOIN (VALUES (1), (2)) AS k(k)
    CROSS JOIN n_productos np
),
prod AS (
    SELECT id_producto,
           ROW_NUMBER() OVER (ORDER BY id_producto) AS idx
    FROM   tmp_tp3_productos
)
SELECT d.id_pedido, pr.id_producto, d.cantidad
FROM   detalles_generados d
JOIN   prod pr ON pr.idx = d.indice_producto_destino;

-- ============================================================
-- VERIFICACIONES (limitadas a las tablas temporales TP3)
-- ============================================================

-- V1: Conteos nuevos
SELECT 'V1 productos' AS check_name, count(*) AS n FROM tmp_tp3_productos;
SELECT 'V1 usuarios'  AS check_name, count(*) AS n FROM tmp_tp3_usuarios;
SELECT 'V1 pedidos'   AS check_name, count(*) AS n FROM tmp_tp3_pedidos;

-- V2: Detalles por pedido = 2 (0 filas esperado)
SELECT id_pedido, count(*) AS n
FROM   detalle_pedido
WHERE  id_pedido IN (SELECT id_pedido FROM tmp_tp3_pedidos)
GROUP  BY id_pedido
HAVING count(*) <> 2;

-- V3: Total exacto por pedido TP3 (pedido.total = SUM(detalle.subtotal); 0 filas esperado)
WITH totals AS (
    SELECT d.id_pedido, SUM(d.subtotal) AS suma
    FROM   detalle_pedido d
    WHERE  d.id_pedido IN (SELECT id_pedido FROM tmp_tp3_pedidos)
    GROUP  BY d.id_pedido
)
SELECT t.id_pedido, t.suma, p.total
FROM   totals t
JOIN   pedido p ON p.id_pedido = t.id_pedido
WHERE  p.total IS DISTINCT FROM t.suma;

-- V4: Subtotal consistente (subtotal = cantidad * precio_unitario; 0 filas esperado)
SELECT id_detalle, id_pedido, subtotal, cantidad * precio_unitario AS esperado
FROM   detalle_pedido
WHERE  id_pedido IN (SELECT id_pedido FROM tmp_tp3_pedidos)
  AND  subtotal IS DISTINCT FROM (cantidad * precio_unitario);

-- V5: Unicidad de mails (0 filas esperado)
SELECT mail, count(*) AS n
FROM   usuario
WHERE  mail LIKE 'tp3_usuario_%@mail.com'
GROUP  BY mail
HAVING count(*) > 1;

-- V6: Sin pedidos sin detalles (0 filas esperado)
SELECT p.id_pedido
FROM   tmp_tp3_pedidos p
WHERE  NOT EXISTS (
    SELECT 1 FROM detalle_pedido d WHERE d.id_pedido = p.id_pedido
);

-- V7: Sin cantidad <= 0 en detalles TP3 (0 filas esperado)
SELECT id_detalle, cantidad
FROM   detalle_pedido
WHERE  id_pedido IN (SELECT id_pedido FROM tmp_tp3_pedidos)
  AND  cantidad <= 0;

-- ============================================================
-- FIN: el usuario decide manualmente en la MISMA sesión.
--
-- Si todas las verificaciones dieron OK (0 filas en los checks
-- que esperan 0 filas) y los conteos son los esperados:
--
--     COMMIT;
--
-- Si algo salió mal y se desea descartar todo:
--
--     ROLLBACK;
--
-- IMPORTANTE: tras el COMMIT (y solo entonces), ejecutar ANALYZE
-- para actualizar las estadísticas ANTES de cualquier EXPLAIN ANALYZE:
--
--     ANALYZE producto, usuario, pedido, detalle_pedido;
-- ============================================================
