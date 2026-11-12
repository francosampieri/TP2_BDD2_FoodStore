-- schema_sqlite.sql
-- Base SQLite 3.37+ para la tablet (FoodStore TP8)
-- Ejecutar desde cero sobre una base vacía.

PRAGMA foreign_keys = ON;

-- Tabla permanente para la instantánea importada desde PostgreSQL (CSV)
CREATE TABLE snapshot_servidor (
    producto_id     INTEGER PRIMARY KEY,
    nombre          TEXT    NOT NULL,
    precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
    stock           INTEGER NOT NULL CHECK (stock >= 0),
    disponible      TEXT    NOT NULL, -- 't'/'f' según CSV de psql
    eliminado       TEXT    NOT NULL, -- 't'/'f' según CSV de psql
    capturado_en    TEXT    NOT NULL
) STRICT;

-- Catálogo local (datos convertidos; referencia para item_borrador)
CREATE TABLE producto_cache (
    producto_id       INTEGER PRIMARY KEY,
    nombre            TEXT    NOT NULL,
    precio_centavos   INTEGER NOT NULL CHECK (precio_centavos >= 0),
    stock_visto       INTEGER NOT NULL CHECK (stock_visto >= 0),
    disponible_visto  INTEGER NOT NULL CHECK (disponible_visto IN (0, 1)),
    eliminado         INTEGER NOT NULL DEFAULT 0 CHECK (eliminado IN (0, 1)),
    capturado_en      TEXT    NOT NULL
) STRICT;

-- Borrador de pedido (solo usuario_id_servidor, sin datos personales)
CREATE TABLE pedido_borrador (
    id_local            TEXT    PRIMARY KEY,
    usuario_id_servidor INTEGER NOT NULL,
    forma_pago          TEXT    NOT NULL CHECK (forma_pago IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA')),
    creado_en           TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
) STRICT;

-- Ítems del borrador (precio congelado al momento de anotar)
CREATE TABLE item_borrador (
    id_local              TEXT    NOT NULL,
    producto_id           INTEGER NOT NULL,
    cantidad              INTEGER NOT NULL CHECK (cantidad > 0),
    precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
    PRIMARY KEY (id_local, producto_id),
    FOREIGN KEY (id_local) REFERENCES pedido_borrador(id_local) ON DELETE CASCADE,
    FOREIGN KEY (producto_id) REFERENCES producto_cache(producto_id)
) STRICT;

-- Cola de sincronización (simulada)
CREATE TABLE cola_sync (
    solicitud_uuid TEXT    PRIMARY KEY,
    id_local       TEXT    NOT NULL,
    estado         TEXT    NOT NULL DEFAULT 'PENDIENTE'
                          CHECK (estado IN ('PENDIENTE', 'CONFLICTO', 'RECHAZADO', 'SIMULADO_APROBADO')),
    motivo         TEXT,
    creada_en      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    FOREIGN KEY (id_local) REFERENCES pedido_borrador(id_local)
) STRICT;

-- Un solo envío pendiente por borrador
CREATE UNIQUE INDEX ux_cola_una_pendiente
    ON cola_sync (id_local)
    WHERE estado = 'PENDIENTE';

-- Catálogo visible offline (precio en pesos)
CREATE VIEW v_catalogo_disponible AS
SELECT
    producto_id,
    nombre,
    precio_centavos / 100.0 AS precio,
    stock_visto
FROM producto_cache
WHERE eliminado = 0
  AND disponible_visto = 1;
