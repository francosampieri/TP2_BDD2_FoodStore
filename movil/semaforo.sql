-- semaforo.sql
-- Clasifica solicitudes PENDIENTE comparando item_borrador vs snapshot_servidor.
-- Solo actualiza SQLite (cola_sync). NO modifica PostgreSQL. SIMULADO_APROBADO
-- no implica crear pedidos ni llamar a sp_crear_pedido.
--
-- Un borrador PENDIENTE sin ítems se clasifica RECHAZADO con motivo
-- 'Borrador sin ítems' (LEFT JOIN a item_borrador).
--
-- Requiere: snapshot_servidor cargada (CSV importado) y datos en cola_sync.
-- Los booleanos del CSV llegan como 't'/'f'.

PRAGMA foreign_keys = ON;

WITH eval AS (
    SELECT
        c.solicitud_uuid,
        SUM(CASE
                WHEN i.producto_id IS NULL
                  OR s.producto_id IS NULL
                  OR s.disponible = 'f'
                  OR s.eliminado  = 't'
                  OR i.cantidad > s.stock
                THEN 1 ELSE 0
            END) AS flag_rojo,
        SUM(CASE
                WHEN i.producto_id IS NOT NULL
                 AND s.producto_id IS NOT NULL
                 AND s.disponible = 't'
                 AND s.eliminado  = 'f'
                 AND i.cantidad <= s.stock
                 AND i.precio_centavos_visto <> s.precio_centavos
                THEN 1 ELSE 0
            END) AS flag_amarillo,
        MIN(CASE
                WHEN i.producto_id IS NULL
                    THEN '1|Borrador sin ítems'
                WHEN s.producto_id IS NULL
                    THEN '2|Producto ' || i.producto_id || ' no encontrado en snapshot'
                WHEN s.eliminado = 't'
                    THEN '3|Producto ' || i.producto_id || ' dado de baja'
                WHEN s.disponible = 'f'
                    THEN '4|Producto ' || i.producto_id || ' no disponible'
                WHEN i.cantidad > s.stock
                    THEN '5|Stock insuficiente: producto ' || i.producto_id
                         || ' (pedido ' || i.cantidad || ', disponible ' || s.stock || ')'
                ELSE NULL
            END) AS motivo_rojo_raw,
        MIN(CASE
                WHEN i.producto_id IS NOT NULL
                 AND s.producto_id IS NOT NULL
                 AND s.disponible = 't'
                 AND s.eliminado  = 'f'
                 AND i.cantidad <= s.stock
                 AND i.precio_centavos_visto <> s.precio_centavos
                    THEN '6|Conflicto de precio: producto ' || i.producto_id
                         || ' (visto ' || i.precio_centavos_visto
                         || ', actual ' || s.precio_centavos || ')'
                ELSE NULL
            END) AS motivo_amarillo_raw
    FROM cola_sync c
    LEFT JOIN item_borrador i
      ON i.id_local = c.id_local
    LEFT JOIN snapshot_servidor s
      ON s.producto_id = i.producto_id
    WHERE c.estado = 'PENDIENTE'
    GROUP BY c.solicitud_uuid
)
UPDATE cola_sync
SET estado = CASE
               WHEN e.flag_rojo > 0 THEN 'RECHAZADO'
               WHEN e.flag_amarillo > 0 THEN 'CONFLICTO'
               ELSE 'SIMULADO_APROBADO'
             END,
    motivo = CASE
               WHEN e.flag_rojo > 0 THEN substr(e.motivo_rojo_raw, 3)
               WHEN e.flag_amarillo > 0 THEN substr(e.motivo_amarillo_raw, 3)
               ELSE NULL
             END
FROM eval e
WHERE cola_sync.solicitud_uuid = e.solicitud_uuid
  AND cola_sync.estado = 'PENDIENTE';

-- Resultado
SELECT solicitud_uuid, id_local, estado, motivo
FROM cola_sync
ORDER BY creada_en, solicitud_uuid;
