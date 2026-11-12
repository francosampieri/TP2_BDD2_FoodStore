# Design — TP8 FoodStore: Base de la Tablet y Sincronización Simulada

## Arquitectura: dos bases, una fuente de verdad

```
┌─────────────────────────────┐        instantánea CSV        ┌────────────────────────┐
│  PostgreSQL (foodstore_u8)  │  ─────────────────────────▶  │   SQLite (foodstore_   │
│                             │                               │   movil.db)            │
│  Fuente de verdad:          │  ◀─────────────────────────  │                        │
│  · precio oficial           │     borradores (simulación)   │  · producto_cache      │
│  · stock real               │                               │  · pedido_borrador     │
│  · ventas confirmadas       │                               │  · item_borrador       │
│  · v_snapshot_movil         │                               │  · cola_sync           │
└─────────────────────────────┘                               └────────────────────────┘
         ▲
         │  sp_crear_pedido (solo en un sistema real;
         │  el TP NO lo ejecuta: SIMULADO_APROBADO ≠ venta)
```

La sincronización en este TP es **unidireccional para la escritura**:
- PostgreSQL → SQLite: instantánea del catálogo (CSV exportado con `\copy`).
- SQLite → simulación: los borradores se evalúan localmente contra la instantánea.
- PostgreSQL nunca recibe escrituras desde la tablet en este TP.

---

## Tablas SQLite

Todas las tablas usan `STRICT`. El script empieza siempre con `PRAGMA foreign_keys = ON`.

### `producto_cache`
Copia del catálogo traída del servidor. Fuente de verdad para el vendedor offline.

| Columna | Tipo SQLite | Restricciones |
|---|---|---|
| `producto_id` | INTEGER | PRIMARY KEY — mismo id que en PostgreSQL (`producto.id_producto`) |
| `nombre` | TEXT | NOT NULL |
| `precio_centavos` | INTEGER | NOT NULL, CHECK >= 0 |
| `stock_visto` | INTEGER | NOT NULL, CHECK >= 0 — **solo orientativo** |
| `disponible_visto` | INTEGER | NOT NULL, CHECK IN (0,1) |
| `eliminado` | INTEGER | NOT NULL DEFAULT 0, CHECK IN (0,1) |
| `capturado_en` | TEXT | NOT NULL — fecha ISO 8601 de la copia |

**Decisión de diseño — centavos:** `NUMERIC(10,2)` de PostgreSQL se convierte a INTEGER
multiplicando por 100. Evita errores de punto flotante en SQLite. La vista del catálogo
divide por 100.0 para mostrarlo.

**Decisión de diseño — stock orientativo:** `stock_visto` refleja el stock al momento
de la instantánea. Puede estar desactualizado. El servidor decide si hay stock real.

### `pedido_borrador`
Un pedido anotado en la tablet, todavía no confirmado como venta.

| Columna | Tipo SQLite | Restricciones |
|---|---|---|
| `id_local` | TEXT | PRIMARY KEY — UUID generado en la tablet (ej: `'aaaa-0001-...'`) |
| `usuario_id_servidor` | INTEGER | NOT NULL — `id_usuario` del vendedor en PostgreSQL |
| `forma_pago` | TEXT | NOT NULL, CHECK IN ('EFECTIVO','TARJETA','TRANSFERENCIA') |
| `creado_en` | TEXT | NOT NULL DEFAULT `strftime('%Y-%m-%dT%H:%M:%SZ','now')` |

**Decisión de diseño — UUID:** sin conexión no hay autoincrement seguro entre tablets.
El UUID garantiza unicidad sin coordinar con el servidor.

**Decisión de diseño — qué no se guarda:** no se almacena nombre, mail, celular ni
contraseña del usuario. Solo `usuario_id_servidor` como referencia al registro en PostgreSQL.

### `item_borrador`
Productos de un borrador, con el precio que vio el cliente al momento de anotar.

| Columna | Tipo SQLite | Restricciones |
|---|---|---|
| `id_local` | TEXT | NOT NULL, FK → `pedido_borrador(id_local)` ON DELETE CASCADE |
| `producto_id` | INTEGER | NOT NULL, FK → `producto_cache(producto_id)` |
| `cantidad` | INTEGER | NOT NULL, CHECK > 0 |
| `precio_centavos_visto` | INTEGER | NOT NULL, CHECK >= 0 — snapshot del precio al anotar |
| PK | — | `(id_local, producto_id)` |

**Decisión de diseño — precio congelado:** `precio_centavos_visto` replica el patrón de
`detalle_pedido.precio_unitario` en PostgreSQL. Si el precio cambia en el servidor antes
de la sincronización, la diferencia produce CONFLICTO en el semáforo.

### `cola_sync`
Registro de cada intento de envío, con su estado y motivo. Es la lista de pendientes.

| Columna | Tipo SQLite | Restricciones |
|---|---|---|
| `solicitud_uuid` | TEXT | PRIMARY KEY — no cambia entre reintentos |
| `id_local` | TEXT | NOT NULL, FK → `pedido_borrador(id_local)` |
| `estado` | TEXT | NOT NULL DEFAULT 'PENDIENTE', CHECK IN ('PENDIENTE','CONFLICTO','RECHAZADO','SIMULADO_APROBADO') |
| `motivo` | TEXT | nullable — descripción del problema si hay rojo o amarillo |
| `creada_en` | TEXT | NOT NULL DEFAULT `strftime('%Y-%m-%dT%H:%M:%SZ','now')` |

**Índice parcial:** `CREATE UNIQUE INDEX ux_cola_una_pendiente ON cola_sync (id_local) WHERE estado = 'PENDIENTE'`
Garantiza que un borrador no tenga dos envíos pendientes simultáneos.

---

## Tabla `snapshot_servidor` (persistente en SQLite)

`snapshot_servidor` es una tabla SQLite permanente, creada en `schema_sqlite.sql`
junto con el resto del esquema. No es temporal: sobrevive entre ejecuciones y se
re-puebla con `DELETE + INSERT` cada vez que se importa una instantánea nueva.
Esto permite comparar dos instantáneas sucesivas y mantener el historial de cuándo
se tomó la última copia.

| Columna | Tipo SQLite STRICT | Restricciones |
|---|---|---|
| `producto_id` | INTEGER | PRIMARY KEY |
| `nombre` | TEXT | NOT NULL |
| `precio_centavos` | INTEGER | NOT NULL, CHECK >= 0 |
| `stock` | INTEGER | NOT NULL, CHECK >= 0 |
| `disponible` | TEXT | NOT NULL — valor `'t'` o `'f'` tal como llega del CSV de psql |
| `eliminado` | TEXT | NOT NULL — valor `'t'` o `'f'` tal como llega del CSV de psql |
| `capturado_en` | TEXT | NOT NULL — timestamp ISO 8601 generado por `now()` en PostgreSQL |

**Por qué se mantiene `'t'`/`'f'` en esta tabla:** el CSV exportado por psql representa
los booleanos como texto. Convertirlos a `0`/`1` al importar requeriría lógica adicional
fuera de SQLite (Python o sed). La conversión se hace en el semáforo con expresiones
`CASE WHEN s.disponible = 'f' THEN …`, que son explícitas y verificables.

**Por qué no se usa como tabla principal del catálogo:** `producto_cache` almacena los datos
ya convertidos a los tipos de SQLite (INTEGER para booleans, centavos para precio) y mantiene
las FK que referencian `item_borrador`. `snapshot_servidor` es el lado de comparación del
semáforo; `producto_cache` es el catálogo que ve el vendedor offline.

---

## Vista del catálogo
```sql
-- Lo que ve el vendedor en pantalla
CREATE VIEW v_catalogo_disponible AS
SELECT producto_id,
       nombre,
       precio_centavos / 100.0 AS precio,
       stock_visto
FROM   producto_cache
WHERE  eliminado = 0 AND disponible_visto = 1;
```

---

## Lógica del semáforo (SQL, sin Python)

El semáforo es una consulta SQL que agrupa por `solicitud_uuid` y clasifica:

```
Para cada solicitud PENDIENTE en cola_sync:
  JOIN item_borrador ON id_local
  LEFT JOIN snapshot_servidor ON producto_id

  Si algún ítem tiene:
    · producto no encontrado en snapshot (LEFT JOIN → NULL)
    · disponible = 'f' (false en CSV de psql)
    · eliminado  = 't'
    · cantidad > stock_visto
    → flag_rojo = 1

  Si algún ítem tiene:
    · precio_centavos_visto ≠ precio_centavos del snapshot
    → flag_amarillo = 1

  Resultado:
    flag_rojo = 1  → RECHAZADO
    flag_amarillo = 1 (y no rojo) → CONFLICTO
    ambos 0 → SIMULADO_APROBADO
```

El UPDATE sobre `cola_sync.estado` y `cola_sync.motivo` se hace con el resultado.
Solo se procesan solicitudes con `estado = 'PENDIENTE'` (idempotencia por filtro).

---

## Mapeo de tipos PostgreSQL → SQLite

| PostgreSQL | SQLite STRICT | Decisión |
|---|---|---|
| `BIGINT GENERATED ALWAYS AS IDENTITY` | `INTEGER` | id del servidor se copia tal cual |
| `NUMERIC(10,2)` precio | `INTEGER` centavos × 100 | evita flotantes |
| `BOOLEAN` | `INTEGER` CHECK IN (0,1) | SQLite no tiene booleano |
| `ENUM forma_pago` | `TEXT` CHECK IN (...) | SQLite no tiene ENUM |
| `TIMESTAMPTZ` | `TEXT` ISO 8601 | SQLite no tiene tipo fecha |
| UUID (nuevo) | `TEXT` | generado por la tablet sin servidor |

---

## Actualización de `producto_cache` (UPSERT)

Cuando llega una instantánea nueva del servidor, `producto_cache` se actualiza con
`INSERT INTO … ON CONFLICT(producto_id) DO UPDATE`. Esta estrategia es preferible a
`INSERT OR REPLACE` porque:

- `INSERT OR REPLACE` equivale a `DELETE + INSERT`: si `item_borrador` tiene una FK hacia
  `producto_cache(producto_id)` y el modo es `ON DELETE CASCADE`, los ítems de borradores
  existentes se perderían silenciosamente.
- `ON CONFLICT … DO UPDATE` modifica la fila en su lugar, conservando todas las FK activas.

**Columnas que se actualizan en el DO UPDATE:**
- `nombre`, `precio_centavos`, `stock_visto`, `disponible_visto` — datos operativos.
- `eliminado` — la marca de baja lógica también se actualiza; es la lápida que llega del
  servidor. Un producto que antes estaba activo y ahora figura con `eliminado = 1` sigue
  existiendo en `producto_cache` (y conserva las referencias de `item_borrador`), pero
  `v_catalogo_disponible` lo excluye automáticamente.
- `capturado_en` — se actualiza con la fecha de la nueva copia.

**Columna que NO se modifica:** `producto_id` (es la clave del conflicto; no tiene sentido
cambiarla).

---

## Flujo de trabajo para el TP

```
# 0. Crear la base SQLite (incluye snapshot_servidor como tabla permanente)
sqlite3 foodstore_movil.db < movil/schema_sqlite.sql

# 1. Crear la vista en PostgreSQL de PRUEBAS
psql -d foodstore_u8 -f postgresql/v_snapshot_movil.sql

# 2. Exportar la instantánea inicial
psql -d foodstore_u8 -c "\copy (SELECT * FROM v_snapshot_movil) TO 'movil/servidor_snapshot.csv' CSV HEADER"

# 3. Importar en snapshot_servidor y actualizar producto_cache con UPSERT
#    (el script cargar_snapshot.sql realiza ambos pasos en orden)
sqlite3 foodstore_movil.db ".import --csv --skip 1 movil/servidor_snapshot.csv snapshot_servidor"
sqlite3 foodstore_movil.db < movil/cargar_snapshot.sql   -- DELETE snapshot_servidor + re-import, luego UPSERT

# 4. Insertar datos de prueba para C2–C6
sqlite3 foodstore_movil.db < movil/datos_casos.sql

# 5. Correr pruebas de la base (C1 y C7)
sqlite3 foodstore_movil.db < movil/pruebas_sqlite.sql

# 6. [Manual] Modificar precios/stock/bajas en PostgreSQL de PRUEBAS para C2–C4
# 7. Exportar instantánea nueva y volver a importar (pasos 2 y 3)

# 8. Correr el semáforo
sqlite3 foodstore_movil.db < movil/semaforo.sql

# 9. Verificar que PostgreSQL no cambió
psql -d foodstore_u8 -c "SELECT COUNT(*) FROM pedido;"
psql -d foodstore_u8 -c "SELECT id_producto, stock FROM producto WHERE id_producto IN (...);"
```

---

## Decisiones de diseño descartadas (para el code review)

| Propuesta | Razón del descarte |
|---|---|
| Usar REAL para precios en SQLite | Punto flotante: 0.1 + 0.2 ≠ 0.3 en IEEE 754. Los centavos en INTEGER son exactos. |
| Guardar el nombre del usuario en pedido_borrador | Dato personal no necesario para vender. Solo se guarda `usuario_id_servidor`. |
| `INSERT OR REPLACE` para actualizar producto_cache | Equivale a DELETE + INSERT: destruye las FK de item_borrador. El UPSERT con ON CONFLICT DO UPDATE conserva las referencias. |
| Usar la hora del teléfono (`strftime('now')`) para decidir qué valor vale en conflictos | La hora del teléfono puede estar mal o manipularse. El servidor decide precios y stock. |
| `UNIQUE` en `cola_sync.id_local` (sin condición parcial) | Un borrador puede reenviarse con nueva solicitud tras resolver un conflicto. El índice parcial `WHERE estado = 'PENDIENTE'` permite exactamente eso. |
