# Tasks — TP8 FoodStore: Base de la Tablet y Sincronización Simulada

> Estas tareas se entregan a OpenCode (agente Build) para que genere los scripts.
> Cada tarea indica el archivo de salida, las restricciones exactas y el caso del TP que verifica.
> Antes de ejecutar cualquier script: crear una copia de la base PostgreSQL (`foodstore_u8`)
> y trabajar exclusivamente sobre ella.

---

## TASK-01 · Esquema SQLite (`movil/schema_sqlite.sql`)

**Generar** un script SQL para SQLite 3.37+ que:

1. Empiece con `PRAGMA foreign_keys = ON;` como primera sentencia ejecutable.
2. Cree las tablas `producto_cache`, `pedido_borrador`, `item_borrador`, `cola_sync`
   y **`snapshot_servidor`** con las columnas, tipos y restricciones exactas de `design.md`.
   - `snapshot_servidor` es una tabla permanente (no temporal), con esquema explícito
     tal como se describe en `design.md`: `producto_id INTEGER PRIMARY KEY`, `nombre TEXT`,
     `precio_centavos INTEGER`, `stock INTEGER`, `disponible TEXT`, `eliminado TEXT`,
     `capturado_en TEXT`. Todos `NOT NULL`. Tabla `STRICT`.
3. Todas las tablas deben declararse con la cláusula `STRICT`.
4. Cree el índice parcial `ux_cola_una_pendiente` sobre `cola_sync (id_local)
   WHERE estado = 'PENDIENTE'`.
5. Cree la vista `v_catalogo_disponible` que filtre `eliminado = 0 AND disponible_visto = 1`
   y divida `precio_centavos / 100.0` para mostrar el precio en pesos.
6. **No incluya** ninguna columna para contraseña, mail, celular ni dato personal
   más allá de `usuario_id_servidor` (INTEGER).
7. El script debe poder ejecutarse desde cero sobre una base vacía sin errores.

**Archivo de salida:** `movil/schema_sqlite.sql`  
**Verifica:** REQ-01, REQ-02, REQ-04 (C1, C7)

---

## TASK-02 · Vista snapshot en PostgreSQL y script de carga (`postgresql/v_snapshot_movil.sql`, `movil/cargar_snapshot.sql`)

**Archivo 1 — `postgresql/v_snapshot_movil.sql`:**  
Crear (o reemplazar) la vista `v_snapshot_movil` en PostgreSQL:

1. Columnas de salida: `producto_id`, `nombre`, `precio_centavos` (precio × 100 como INTEGER),
   `stock`, `disponible`, `eliminado`, `capturado_en` (`now()`).
2. `eliminado` debe ser `(p.eliminado OR c.eliminado)` — la baja de la categoría también
   marca el producto como dado de baja para la tablet (lápida).
3. La vista une `producto p JOIN categoria c ON c.id_categoria = p.id_categoria`.
4. No aplica `WHERE eliminado = FALSE`: los productos dados de baja también viajan como lápidas.
5. **No expone** columnas de `usuario` ni datos personales.

**Archivo 2 — `movil/cargar_snapshot.sql`:**  
Script SQLite que, después de que el operador haya importado el CSV en `snapshot_servidor`, actualiza `producto_cache` mediante UPSERT:

```sql
-- Se ejecuta en SQLite después de importar el CSV en snapshot_servidor
INSERT INTO producto_cache (
    producto_id, nombre, precio_centavos, stock_visto,
    disponible_visto, eliminado, capturado_en
)
SELECT
    producto_id,
    nombre,
    precio_centavos,
    stock,
    CASE disponible  WHEN 't' THEN 1 ELSE 0 END,
    CASE eliminado   WHEN 't' THEN 1 ELSE 0 END,
    capturado_en
FROM snapshot_servidor
ON CONFLICT(producto_id) DO UPDATE SET
    nombre           = excluded.nombre,
    precio_centavos  = excluded.precio_centavos,
    stock_visto      = excluded.stock,
    disponible_visto = excluded.disponible_visto,
    eliminado        = excluded.eliminado,
    capturado_en     = excluded.capturado_en;
```

La conversión `'t'`/`'f'` → `1`/`0` ocurre aquí, una sola vez.
El `ON CONFLICT DO UPDATE` preserva las FK de `item_borrador` al no borrar y re-insertar.

**Archivos de salida:** `postgresql/v_snapshot_movil.sql`, `movil/cargar_snapshot.sql`  
**Verifica:** REQ-03 (C4 — lápida viaja a la tablet y actualiza eliminado sin romper referencias)

---

## TASK-03 · Pruebas SQLite (`movil/pruebas_sqlite.sql`)

**Generar** un script SQL para SQLite que demuestre, en orden:

**Bloque A — Transacción exitosa (REQ-02):**
1. `BEGIN` → `INSERT INTO pedido_borrador` con:
   - `id_local = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'`
   - `usuario_id_servidor = 2`, `forma_pago = 'EFECTIVO'`.
2. `INSERT INTO item_borrador` (misma id_local, `producto_id` existente en `producto_cache`,
   `cantidad = 2`, `precio_centavos_visto` válido).
3. `INSERT INTO cola_sync` con `solicitud_uuid = 'b1c2d3e4-f5a6-4b7c-8d9e-0f1a2b3c4d5e'`,
   misma id_local, estado por defecto.
4. `COMMIT`.
5. `SELECT` que muestra las tres filas recién creadas.

**Bloque B — ROLLBACK (REQ-02):**
1. `BEGIN` → `INSERT INTO pedido_borrador` con `id_local = 'c2d3e4f5-a6b7-4c8d-9e0f-1a2b3c4d5e6f'`.
2. `ROLLBACK`.
3. `SELECT COUNT(*)` que confirma que no quedó la fila.

**Bloque C — Caso C1 (REQ-01):**
1. `SELECT` sobre `v_catalogo_disponible` que devuelve filas (simula consulta sin servidor).
2. Comentario explícito: "Esta consulta funciona sin conexión a PostgreSQL."

**Bloque D — Caso C7 (REQ-02):**
1. `BEGIN` → intento de `INSERT INTO item_borrador` con `cantidad = 0`
   (debe fallar por CHECK).
2. `ROLLBACK` y `SELECT COUNT(*)` que confirma 0 filas nuevas.
3. `BEGIN` → intento de `INSERT INTO item_borrador` con un `producto_id` que no existe
   en `producto_cache` (debe fallar por FK con `PRAGMA foreign_keys = ON`).
4. `ROLLBACK` y `SELECT COUNT(*)` que confirma 0 filas nuevas.

**Archivo de salida:** `movil/pruebas_sqlite.sql`  
**Verifica:** C1, C7 completo

---

## TASK-04 · Semáforo (`movil/semaforo.sql`)

**Generar** un script SQL para SQLite que:

1. Asuma que `snapshot_servidor` ya existe (importada desde CSV).
2. Use un único `UPDATE cola_sync SET estado = ..., motivo = ...` con una subconsulta
   o CTE que calcule el estado para cada `solicitud_uuid` con `estado = 'PENDIENTE'`.
3. La lógica de clasificación (en SQL, sin Python):
   - `flag_rojo`: algún ítem tiene `s.producto_id IS NULL` (LEFT JOIN miss),
     `s.disponible = 'f'`, `s.eliminado = 't'`, o `i.cantidad > s.stock`.
   - `flag_amarillo`: no hay rojo y algún ítem tiene `i.precio_centavos_visto <> s.precio_centavos`.
   - Resultado: `CASE WHEN flag_rojo > 0 THEN 'RECHAZADO' WHEN flag_amarillo > 0 THEN 'CONFLICTO' ELSE 'SIMULADO_APROBADO' END`.
4. El `motivo` debe describir el primer problema encontrado (ej: "Stock insuficiente: producto 5").
5. **Solo procesa** filas con `estado = 'PENDIENTE'` — las ya evaluadas no se re-procesan.
6. No modifica ninguna tabla de PostgreSQL.
7. Al final del script: `SELECT solicitud_uuid, id_local, estado, motivo FROM cola_sync ORDER BY creada_en`.

**Nota sobre el CSV de psql:** los booleanos llegan como texto `'t'`/`'f'`.
La comparación debe ser `s.disponible = 'f'` y `s.eliminado = 't'`.

**Archivo de salida:** `movil/semaforo.sql`  
**Verifica:** REQ-03 (C2, C3, C4, C5), REQ-04 (C6)

---

## TASK-05 · Datos de prueba para los casos C2–C6 (`movil/datos_casos.sql`)

**Generar** un script SQL para SQLite que inserte los borradores de prueba necesarios
para demostrar los cinco casos. Todos los UUID deben seguir el formato canónico
`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` (versión 4, dígitos hexadecimales reales).

| Caso | `id_local` del borrador | `solicitud_uuid` inicial | Situación a preparar |
|---|---|---|---|
| C2 | `'c2000000-0000-4000-8000-000000000002'` | `'c2000000-0000-4000-8000-100000000002'` | precio del producto X será subido en el servidor |
| C3 | `'c3000000-0000-4000-8000-000000000003'` | `'c3000000-0000-4000-8000-100000000003'` | cantidad pedida = stock actual + 1 |
| C4 | `'c4000000-0000-4000-8000-000000000004'` | `'c4000000-0000-4000-8000-100000000004'` | producto Y será dado de baja en el servidor |
| C5 | `'c5000000-0000-4000-8000-000000000005'` | `'c5000000-0000-4000-8000-100000000005'` | borrador sin ningún cambio en el servidor |
| C6 | `'c6000000-0000-4000-8000-000000000006'` | `'c6000000-0000-4000-8000-100000000006'` | misma solicitud se intenta insertar dos veces |

**Para C2 — flujo de conflicto y reenvío:**
El script debe documentar el flujo completo en comentarios:
1. La solicitud inicial se evalúa como CONFLICTO porque el precio cambió.
2. El cliente acepta el nuevo precio: se hace `UPDATE item_borrador SET precio_centavos_visto = <nuevo_precio>`.
3. Se crea una **nueva** fila en `cola_sync` para el mismo `id_local` del borrador,
   con un `solicitud_uuid` distinto (`'c2000000-0000-4000-8000-200000000002'`)
   y estado `'PENDIENTE'`. La solicitud anterior queda con estado `'CONFLICTO'`.
4. Al correr el semáforo de nuevo, la nueva solicitud da `SIMULADO_APROBADO`.
El índice parcial `ux_cola_una_pendiente` permite esta segunda solicitud porque la
primera ya no tiene estado `'PENDIENTE'`.

**Para C6 — demostración de idempotencia:**
El script debe incluir:
1. El `INSERT` de la solicitud inicial (estado `'PENDIENTE'`).
2. Un segundo `INSERT` con el **mismo** `solicitud_uuid` comentado, con la instrucción:
   "Descomentar para ver el error de PRIMARY KEY."
3. Después de demostrar el error (o en el mismo script, siempre ejecutable):
   un `SELECT solicitud_uuid, id_local, estado, motivo FROM cola_sync WHERE id_local = 'c6000000-0000-4000-8000-000000000006'`
   que confirme que el estado sigue siendo `'PENDIENTE'` y no hay fila duplicada.

**Archivo de salida:** `movil/datos_casos.sql`  
**No ejecutar aún:** los datos del servidor (precios, stock, baja lógica) se modifican
manualmente en PostgreSQL de PRUEBAS antes de exportar la instantánea nueva.

---

## Orden de ejecución para el corrector

```
# 0. Crear la base SQLite (crea producto_cache, pedido_borrador,
#    item_borrador, cola_sync y snapshot_servidor como tabla permanente)
sqlite3 movil/foodstore_movil.db < movil/schema_sqlite.sql

# 1. Crear la vista en PostgreSQL de PRUEBAS
psql -d foodstore_u8 -f postgresql/v_snapshot_movil.sql

# 2. Exportar la instantánea inicial
psql -d foodstore_u8 -c "\copy (SELECT * FROM v_snapshot_movil) TO 'movil/servidor_snapshot.csv' CSV HEADER"

# 3a. Limpiar snapshot_servidor e importar el CSV nuevo
sqlite3 movil/foodstore_movil.db "DELETE FROM snapshot_servidor;"
sqlite3 movil/foodstore_movil.db ".import --csv --skip 1 movil/servidor_snapshot.csv snapshot_servidor"

# 3b. Actualizar producto_cache con UPSERT (convierte 't'/'f' a 1/0)
sqlite3 movil/foodstore_movil.db < movil/cargar_snapshot.sql

# 4. Insertar datos de prueba para C2–C6
sqlite3 movil/foodstore_movil.db < movil/datos_casos.sql

# 5. Correr pruebas de la base (C1 y C7)
sqlite3 movil/foodstore_movil.db < movil/pruebas_sqlite.sql

# 6. [Manual] Modificar precios/stock/bajas en PostgreSQL de PRUEBAS para C2–C4,
#    luego repetir pasos 2, 3a y 3b para traer la instantánea nueva

# 7. Correr el semáforo
sqlite3 movil/foodstore_movil.db < movil/semaforo.sql

# 8. Verificar que PostgreSQL no cambió
psql -d foodstore_u8 -c "SELECT COUNT(*) FROM pedido;"
psql -d foodstore_u8 -c "SELECT id_producto, stock FROM producto WHERE id_producto IN (...);"
```
