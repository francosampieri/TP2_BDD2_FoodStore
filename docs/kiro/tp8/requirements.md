# Requirements — TP8 FoodStore: Base de la Tablet y Sincronización Simulada

## Contexto

Food Store opera un food truck en una feria sin conexión estable.
La tablet necesita mostrar el catálogo y registrar borradores de pedido aunque no haya señal.
Cuando vuelve la conexión, los borradores se comparan contra una instantánea del servidor
usando un semáforo (RECHAZADO / CONFLICTO / SIMULADO_APROBADO).

**Regla de oro:** el móvil propone, el servidor dispone.
PostgreSQL es la única fuente de verdad para precios, stock y ventas.
SIMULADO_APROBADO **no** crea un pedido ni modifica nada en PostgreSQL.

---

## Restricciones globales

- Toda la base de la tablet usa SQLite 3.37+ con tablas `STRICT`.
- Se activa `PRAGMA foreign_keys = ON` al abrir la base, antes de cualquier operación.
- Los precios se almacenan como enteros en centavos (sin punto flotante).
- Nunca se almacenan en SQLite: contraseñas, mails, celulares ni datos personales
  que no sean estrictamente necesarios para identificar al vendedor asignado.
- La tablet nunca ejecuta `UPDATE producto SET stock` ni ninguna otra escritura sobre
  las tablas de PostgreSQL.
- La simulación opera únicamente sobre los datos de SQLite y sobre la instantánea CSV.

---

## REQ-01 · Consulta del catálogo sin conexión

```
WHEN el vendedor consulta el catálogo disponible
THE SYSTEM SHALL devolver los productos de producto_cache
     donde eliminado = 0 AND disponible_visto = 1,
     sin requerir conexión a PostgreSQL.
```

**Caso que lo prueba:** C1  
**Parada del apunte:** 1 y 3  
**Criterio de aceptación:** la consulta devuelve filas correctas con la base SQLite sola,
sin que el servidor PostgreSQL esté accesible en ese momento.

---

## REQ-02 · Atomicidad del borrador

```
WHEN el vendedor registra un borrador de pedido
THE SYSTEM SHALL insertar en una única transacción
     pedido_borrador + item_borrador + cola_sync (estado PENDIENTE),
     de modo que si cualquier operación falla, no quede
     ninguna de las tres filas guardada.
```

**Caso que lo prueba:** C7 (cantidad = 0 o producto inexistente → error, no quedan filas)  
**Parada del apunte:** 3 y 4  
**Criterio de aceptación:**
- Un `BEGIN … COMMIT` con datos válidos crea las tres filas.
- Un `BEGIN … ROLLBACK`, o un `BEGIN` que falla por CHECK/FK,
  no deja ninguna fila nueva en ninguna de las tres tablas.
- `PRAGMA foreign_keys = ON` está activo: un item_borrador que referencia
  un producto_id inexistente en producto_cache falla con error de FK.

---

## REQ-03 · Semáforo de sincronización

```
WHEN se ejecuta la simulación sobre una solicitud en estado PENDIENTE
THE SYSTEM SHALL evaluar cada ítem del borrador contra snapshot_servidor y:
  - marcar la solicitud como RECHAZADO si algún ítem tiene
    stock insuficiente, producto no disponible o producto dado de baja;
  - marcar la solicitud como CONFLICTO si no hay rojo
    pero algún precio_centavos_visto difiere del precio actual;
  - marcar la solicitud como SIMULADO_APROBADO si todo coincide;
  - guardar el motivo en cola_sync.motivo.
```

**Casos que lo prueban:** C2 (CONFLICTO → luego SIMULADO_APROBADO), C3 (RECHAZADO por stock),
C4 (RECHAZADO por baja lógica), C5 (SIMULADO_APROBADO)  
**Parada del apunte:** 5, 6 y 7  
**Criterio de aceptación:**
- Si un borrador tiene un ítem rechazado y otro con conflicto de precio, el resultado
  final es RECHAZADO (el rojo gana).
- Ninguna operación en PostgreSQL es modificada durante la simulación.
- Una consulta `SELECT COUNT(*) FROM pedido` en PostgreSQL devuelve el mismo
  número antes y después de correr la simulación.

---

## REQ-04 · Idempotencia del envío

```
WHEN se intenta insertar una solicitud cuyo solicitud_uuid
     ya existe en cola_sync
THE SYSTEM SHALL rechazar el INSERT con error de clave primaria,
     devolver el estado ya registrado sin re-evaluar,
     y no crear una fila duplicada en cola_sync.
```

**Caso que lo prueba:** C6  
**Parada del apunte:** 8  
**Criterio de aceptación:**
- Un segundo `INSERT INTO cola_sync` con el mismo `solicitud_uuid` falla
  con violación de PRIMARY KEY.
- El estado guardado en la primera evaluación se conserva sin cambios.
- En un sistema real, la protección definitiva estaría en PostgreSQL mediante
  una tabla `solicitud_movil` con `solicitud_uuid PRIMARY KEY` y `ON CONFLICT DO NOTHING`
  dentro de la misma transacción que ejecuta `sp_crear_pedido`
  (el TP simula este comportamiento en SQLite sin tocar PostgreSQL).
