# Informe de concurrencia — TP2 FoodStore

## Entorno y criterio de seguridad

- Motor: PostgreSQL 17.
- Cliente: DBeaver.
- Base de pruebas: `foodstore_tp2`.
- Sesión A: `pg_backend_pid()` = `40428`.
- Sesión B: `pg_backend_pid()` = `30880`.
- Antes de aplicar cambios estructurales se realizó un respaldo de la copia de trabajo. Los cambios temporales de las pruebas se cerraron con `ROLLBACK` o se revirtieron en `foodstore_tp2`.

---

## 1. Lectura no repetible

### Cómo se reprodujo

Se utilizó `producto.id_producto = 11`.

**Sesión A — Read Committed**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT stock
FROM producto
WHERE id_producto = 11;
```

**Sesión B**

```sql
BEGIN;
UPDATE producto SET stock = stock - 1 WHERE id_producto = 11;
COMMIT;
```

**Sesión A, sin cerrar la transacción**

```sql
SELECT stock
FROM producto
WHERE id_producto = 11;
```

Luego se cerró A con `ROLLBACK` y se restauró el stock en B con `stock = stock + 1` y `COMMIT`.

### Qué se observó

| Aislamiento | Primera lectura de A | Segunda lectura de A luego del COMMIT de B |
|---|---:|---:|
| `READ COMMITTED` | 20 | 19 |

La misma consulta devolvió un valor distinto dentro de la transacción A.

### Explicación de la IA

> En PostgreSQL, `READ COMMITTED` toma una nueva instantánea de datos al inicio de cada sentencia. Por eso, después de que B confirma el `UPDATE`, la segunda consulta de A puede ver la versión nueva de la fila. El efecto se evita usando `REPEATABLE READ`, que conserva la instantánea obtenida por la transacción.

### Verificación en el motor

Se repitió el experimento con:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT stock FROM producto WHERE id_producto = 11;
```

B volvió a descontar una unidad y confirmó. A repitió la consulta antes de terminar su transacción.

| Aislamiento | Primera lectura de A | Segunda lectura de A luego del COMMIT de B |
|---|---:|---:|
| `REPEATABLE READ` | 20 | 20 |

### Conclusión

La explicación de la IA se confirmó. `REPEATABLE READ` evitó la lectura no repetible al mantener una instantánea consistente durante la transacción A.

---

## 2. Lectura fantasma

### Cómo se reprodujo

Se contaron productos vigentes de la categoría `id_categoria = 1`.

**Sesión A — Read Committed**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT COUNT(*) AS cantidad
FROM producto
WHERE id_categoria = 1
  AND eliminado = FALSE;
```

**Sesión B**

```sql
BEGIN;

INSERT INTO producto (
  nombre_producto, precio, stock, disponible, id_categoria
)
VALUES (
  'TP2_Fantasma_RC', 1.00, 1, TRUE, 1
);

COMMIT;
```

**Sesión A, sin cerrar la transacción**

```sql
SELECT COUNT(*) AS cantidad
FROM producto
WHERE id_categoria = 1
  AND eliminado = FALSE;
```

Luego A hizo `ROLLBACK`; B marcó el producto temporal como eliminado y confirmó.

### Qué se observó

| Aislamiento | Primer `COUNT(*)` de A | Segundo `COUNT(*)` de A |
|---|---:|---:|
| `READ COMMITTED` | 3 | 4 |

La segunda consulta de A incluyó una nueva fila que cumplía la condición del `WHERE`.

### Explicación de la IA

> La lectura fantasma ocurre cuando otra transacción confirma una fila nueva que coincide con el predicado de una consulta. Con `READ COMMITTED`, cada sentencia de A usa una instantánea nueva y puede incluir esa fila. En PostgreSQL, `REPEATABLE READ` mantiene la instantánea de A y evita que el segundo `COUNT` vea la fila insertada por B.

### Verificación en el motor

Se repitió el experimento con `BEGIN ISOLATION LEVEL REPEATABLE READ`, usando el producto temporal `TP2_Fantasma_RR`.

| Aislamiento | Primer `COUNT(*)` de A | Segundo `COUNT(*)` de A |
|---|---:|---:|
| `REPEATABLE READ` | 3 | 3 |

### Conclusión

La explicación de la IA se confirmó. En PostgreSQL, `REPEATABLE READ` evitó que A leyera la fila fantasma confirmada por B durante su transacción.

---

## 3. Espera por bloqueo

### Cómo se reprodujo

Se usó el mismo producto `id_producto = 11`.

**Sesión A**

```sql
BEGIN;

SELECT id_producto, nombre_producto, stock
FROM producto
WHERE id_producto = 11
FOR UPDATE;
```

**Sesión B, mientras A seguía abierta**

```sql
BEGIN;

SELECT id_producto, nombre_producto, stock
FROM producto
WHERE id_producto = 11
FOR UPDATE;
```

### Qué se observó

La consulta de B quedó ejecutándose y no devolvió la fila mientras A conservaba el bloqueo. Al ejecutar `COMMIT` en A, B se destrabó y obtuvo la fila. Finalmente B ejecutó `ROLLBACK`.

### Explicación de la IA

> `SELECT ... FOR UPDATE` toma un bloqueo de fila para impedir que otra transacción tome un bloqueo incompatible sobre la misma fila. Por eso B espera hasta que A haga `COMMIT` o `ROLLBACK`. El mecanismo no es un error: serializa el acceso cuando la operación necesita exclusividad.

### Verificación en el motor

El comportamiento observado coincidió con la explicación: B quedó esperando y continuó inmediatamente después del `COMMIT` de A.

### Conclusión

La explicación de la IA se confirmó. `FOR UPDATE` protege la fila frente a accesos concurrentes incompatibles; la segunda sesión debe esperar la liberación del bloqueo.

---

## Resumen

Se reprodujeron los tres escenarios obligatorios sobre tablas del proyecto FoodStore. En los tres casos, la explicación de la IA fue verificada contra el comportamiento real de PostgreSQL 17 en `foodstore_tp2`.
