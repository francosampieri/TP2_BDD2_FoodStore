# Ejercicio de lectura crítica — TP2 FoodStore

Este ejercicio analiza los scripts genéricos de la consigna antes de ejecutarlos. Ninguno de los dos se ejecutó sobre `foodstore` ni sobre `foodstore_tp2`.

## Script 1 — Baja de funciones retiradas de cartel

### Script recibido

```sql
UPDATE funcion
SET activa = FALSE;
```

### Qué filas afectaría realmente

La sentencia intenta actualizar **todas** las filas de `funcion`, sin importar su fecha, estado o relación con una película retirada. Las filas que ya tenían `activa = FALSE` conservan ese valor, pero igualmente forman parte del alcance de la sentencia; todas las funciones activas quedan desactivadas.

### Por qué no cumple la consigna

El comentario habla de funciones retiradas de cartel, pero la consulta no tiene `WHERE`. No existe ningún criterio que distinga una función retirada de una función todavía vigente. Ejecutarla dejaría inactivas todas las funciones activas del sistema.

### Versión corregida

La consigna no informa el nombre de la columna que identifica una función retirada, por lo que no es seguro inventarlo y ejecutar la sentencia. Si el modelo genérico tiene una columna `fecha` que representa la fecha de la función, una versión correcta sería:

```sql
UPDATE funcion
SET activa = FALSE
WHERE fecha < CURRENT_DATE
  AND activa = TRUE;
```

Si la regla real usa otra columna, por ejemplo `fecha_fin_cartelera` o un estado de la película, el predicado debe adaptarse a ese modelo antes de ejecutarse. La condición `activa = TRUE` limita el cambio a filas que necesitan la baja lógica.

---

## Script 2 — Categorías sin productos asociados

### Script recibido

```sql
DELETE FROM categoria
WHERE id NOT IN (SELECT categoria_id FROM producto);
```

### Qué filas afectaría realmente

Si `producto.categoria_id` no contiene valores `NULL`, elimina físicamente cada categoría sin productos asociados. Esto no realiza una baja lógica y puede romper el historial o las claves foráneas del sistema.

Si la subconsulta devuelve al menos un `NULL`, `NOT IN` deja de ser seguro: para una categoría sin coincidencia, la comparación se vuelve `UNKNOWN`, no `TRUE`. En ese caso puede no borrarse ninguna categoría, incluso si existen categorías sin productos.

### Por qué no cumple la consigna

El script supone que la subconsulta nunca devuelve `NULL` y hace un borrado físico. La intención es limpiar categorías sin productos; la consulta no maneja el caso `NULL` y tampoco respeta un diseño que use baja lógica.

### Versión corregida para el esquema genérico

```sql
DELETE FROM categoria c
WHERE NOT EXISTS (
    SELECT 1
    FROM producto p
    WHERE p.categoria_id = c.id
);
```

`NOT EXISTS` no presenta el problema semántico de `NOT IN` con valores `NULL`.

### Adaptación segura al esquema FoodStore

FoodStore usa `id_categoria` y baja lógica mediante `eliminado`. La adaptación no borra filas y considera únicamente productos vigentes:

```sql
UPDATE categoria c
SET eliminado = TRUE
WHERE c.eliminado = FALSE
  AND NOT EXISTS (
      SELECT 1
      FROM producto p
      WHERE p.id_categoria = c.id_categoria
        AND p.eliminado = FALSE
  );
```

Antes de ejecutar una sentencia de este tipo se debe aplicar el protocolo de copia, transacción y respaldo.
