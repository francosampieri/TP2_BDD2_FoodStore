# Spec de restricciones de integridad — TP2 FoodStore

## Regla 1 — Transiciones válidas de estado del pedido

Tabla: `pedido`  
Columna: `estado`

Un pedido solo puede avanzar según este flujo:

- `PENDIENTE` → `CONFIRMADO` o `CANCELADO`.
- `CONFIRMADO` → `TERMINADO` o `CANCELADO`.
- `TERMINADO` y `CANCELADO` son estados finales y no pueden cambiar.

Se permite conservar el mismo estado en una actualización que no lo modifique.

## Regla 2 — Baja lógica de categorías con productos vigentes

Tabla: `categoria`  
Columnas: `eliminado`, `id_categoria`

No se puede cambiar `categoria.eliminado` de `FALSE` a `TRUE` si existe al menos un registro en `producto` con el mismo `id_categoria` y `producto.eliminado = FALSE`.

La baja lógica debe permitirse cuando la categoría no tenga productos vigentes asociados.