CREATE DATABASE FoodStore;

-- Tipos enumerados
CREATE TYPE rol           AS ENUM ('ADMIN','USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE','CONFIRMADO',
                                   'TERMINADO','CANCELADO');
CREATE TYPE forma_pago    AS ENUM ('TARJETA','TRANSFERENCIA','EFECTIVO');

CREATE TABLE categoria (
    id_categoria          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_categoria      VARCHAR(80)  NOT NULL UNIQUE,
    descripcion_categoria VARCHAR(255),
    eliminado   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE producto (
    id_producto           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_producto       VARCHAR(120) NOT NULL,
    precio       NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    descripcion_producto  VARCHAR(255),
    stock        INTEGER      NOT NULL DEFAULT 0 CHECK (stock >= 0),
    imagen       VARCHAR(255),
    disponible   BOOLEAN      NOT NULL DEFAULT TRUE,
    id_categoria BIGINT       NOT NULL REFERENCES categoria(id_categoria),
    eliminado    BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE usuario (
    id_usuario         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_usuario      VARCHAR(80)  NOT NULL,
    apellido    VARCHAR(80)  NOT NULL,
    mail        VARCHAR(120) NOT NULL UNIQUE,
    celular     VARCHAR(30),
    contrasena  VARCHAR(255) NOT NULL,
    rol         rol          NOT NULL DEFAULT 'USUARIO',
    eliminado   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE pedido (
    id_pedido         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha      DATE          NOT NULL DEFAULT CURRENT_DATE,
    estado     estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    total      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    forma_pago forma_pago    NOT NULL,
    id_usuario BIGINT        NOT NULL REFERENCES usuario(id_usuario),
    eliminado  BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE detalle_pedido (
    id_detalle          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cantidad       INTEGER       NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal       NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    id_pedido      BIGINT        NOT NULL REFERENCES pedido(id_pedido) ON DELETE RESTRICT,
    id_producto   BIGINT        NOT NULL REFERENCES producto(id_producto),
    eliminado      BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (id_pedido, id_producto)
);

-- ÍNDICES

CREATE INDEX idx_producto_id_categoria
    ON producto (id_categoria);

CREATE INDEX idx_id_pedido_usuario
    ON pedido (id_usuario);

CREATE INDEX idx_producto_nombre
    ON producto (nombre_producto)
    WHERE eliminado = FALSE;

CREATE INDEX idx_pedido_fecha
    ON pedido (fecha);
