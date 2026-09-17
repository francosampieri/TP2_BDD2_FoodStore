# Especificación de Vistas — TP5 FoodStore Parte B

> Este documento especifica las tres vistas nuevas para la Parte B del TP5.
> No contiene `CREATE VIEW` ni DDL de ningún tipo.
> Las vistas existentes en `Objects.sql` (`v_productos_vigentes`, `v_pedidos_resumen`,
> `v_pedido_detalle`, `v_categorias_vigentes`) no se modifican ni reemplazan.

---

## Relación con las vistas existentes

| Vista existente (`Objects.sql`) | Diferencia con la vista TP5 equivalente |
|---|---|
| `v_productos_vigentes` | Filtra `c.eliminado = FALSE`; expone `imagen`, `descripcion_producto` y `disponible` pero no `id_categoria`. No es una vista de reporte estructurado por categoría. |
| `v_pedidos_resumen` | Concatena nombre y apellido en una sola columna `usuario`; no expone `id_usuario`, `mail` ni columnas de identidad separadas. |
| `v_pedido_detalle` | No expone `id_producto` como columna de salida explícita y filtra solo `dp.eliminado`; no incluye productos históricos eliminados de forma documentada. |

Las vistas TP5 son complementarias: amplían la proyección, corrigen omisiones para
casos de uso de reporte y hacen explícitas las reglas de seguridad y de histórico.

---

## Vista 1 — `v_tp5_productos_categoria`

### Objetivo de reporte
Proveer una vista de catálogo completa para reportes de gestión y pantallas de
listado: cada producto vigente aparece con su categoría desnormalizada, su precio
actual y su stock disponible. Es la base para reportes de inventario por categoría
y para cualquier consulta que necesite filtrar o agrupar productos por nombre de
categoría sin hacer el JOIN manualmente.

### Tablas y JOINs
| Tabla | Rol | Condición de JOIN |
|---|---|---|
| `producto` | Tabla principal | — |
| `categoria` | Tabla de referencia | `categoria.id_categoria = producto.id_categoria` (INNER JOIN) |

El JOIN es `INNER` porque todo producto tiene una categoría por restricción de FK
(`id_categoria NOT NULL`), y porque si la categoría está eliminada el producto
no debe aparecer en la vista (se excluye de forma natural).

### Columnas expuestas
| Columna en la vista | Expresión de origen | Descripción |
|---|---|---|
| `id_producto` | `producto.id_producto` | Identificador del producto |
| `nombre_producto` | `producto.nombre_producto` | Nombre del producto |
| `precio` | `producto.precio` | Precio unitario vigente |
| `stock` | `producto.stock` | Unidades en stock |
| `disponible` | `producto.disponible` | Indicador de disponibilidad operativa |
| `id_categoria` | `categoria.id_categoria` | Identificador de la categoría |
| `nombre_categoria` | `categoria.nombre_categoria` | Nombre de la categoría |

### Filtros de vigencia
- `producto.eliminado = FALSE` — excluye productos dados de baja lógica.
- `categoria.eliminado = FALSE` — excluye categorías dadas de baja lógica.

Ambos filtros son independientes y se aplican en la cláusula `WHERE` de la vista.
Un producto cuya categoría esté eliminada no debe aparecer en el catálogo vigente.

### Regla de seguridad
No aplica columnas sensibles. La vista no incluye `descripcion_producto`,
`imagen` ni `created_at`; son columnas operativas que quedan fuera del
alcance de reporte de esta vista y pueden exponerse en una vista más
detallada si fuera necesario.

### Consulta manual equivalente (para verificación posterior)
```sql
SELECT p.id_producto,
       p.nombre_producto,
       p.precio,
       p.stock,
       p.disponible,
       c.id_categoria,
       c.nombre_categoria
FROM   producto  p
JOIN   categoria c ON c.id_categoria = p.id_categoria
WHERE  p.eliminado = FALSE
  AND  c.eliminado = FALSE
ORDER  BY c.id_categoria, p.id_producto;
```

Para verificar la vista una vez creada, el resultado de
`SELECT * FROM v_tp5_productos_categoria ORDER BY id_categoria, id_producto`
debe ser idéntico al de la consulta manual anterior.

---

## Vista 2 — `v_tp5_pedidos_usuario`

### Objetivo de reporte
Proveer una vista de pedidos con identidad completa del usuario para reportes
administrativos y auditoría: fecha, estado, forma de pago, total y los datos
del cliente (nombre, apellido, mail) en columnas separadas. A diferencia de
`v_pedidos_resumen`, que concatena nombre y apellido y omite el mail, esta vista
expone cada campo de identidad como columna independiente para permitir filtrado,
ordenamiento y exportación por campo.

### Tablas y JOINs
| Tabla | Rol | Condición de JOIN |
|---|---|---|
| `pedido` | Tabla principal | — |
| `usuario` | Tabla de referencia | `usuario.id_usuario = pedido.id_usuario` (INNER JOIN) |

El JOIN es `INNER` porque todo pedido tiene un usuario por FK (`id_usuario NOT NULL`).
Si el usuario está eliminado el pedido no debe aparecer en la vista de reportes
activos, ya que el usuario no tiene cuenta vigente.

### Columnas expuestas
| Columna en la vista | Expresión de origen | Descripción |
|---|---|---|
| `id_pedido` | `pedido.id_pedido` | Identificador del pedido |
| `fecha` | `pedido.fecha` | Fecha de creación del pedido |
| `estado` | `pedido.estado` | Estado del ciclo de vida del pedido |
| `forma_pago` | `pedido.forma_pago` | Método de pago utilizado |
| `total` | `pedido.total` | Total calculado por trigger |
| `id_usuario` | `usuario.id_usuario` | Identificador del usuario |
| `nombre_usuario` | `usuario.nombre_usuario` | Nombre del usuario |
| `apellido` | `usuario.apellido` | Apellido del usuario |
| `mail` | `usuario.mail` | Dirección de correo del usuario |

### Filtros de vigencia
- `pedido.eliminado = FALSE` — excluye pedidos dados de baja lógica.
- `usuario.eliminado = FALSE` — excluye usuarios dados de baja lógica.

Ambos filtros son independientes. El pedido histórico del usuario 8
(pedido #1, `data.sql`) no aparecerá en esta vista porque ese usuario
tiene `eliminado = TRUE`; si se necesitara acceder a pedidos históricos
de usuarios eliminados, se requiere una vista separada sin el filtro
de usuario.

### Regla de seguridad
**La columna `usuario.contrasena` nunca debe incluirse en esta vista
ni en ninguna variante de ella.** La vista expone `mail` como dato de
contacto para uso administrativo; si la vista se usa en un contexto de
menor confianza (reportes externos, exportaciones), `mail` puede
eliminarse de la proyección en esa capa, pero no en esta especificación
base. Otras columnas sensibles equivalentes que tampoco deben incluirse:
`celular` (dato personal) y `rol` (dato de autorización interno).

### Consulta manual equivalente (para verificación posterior)
```sql
SELECT ped.id_pedido,
       ped.fecha,
       ped.estado,
       ped.forma_pago,
       ped.total,
       u.id_usuario,
       u.nombre_usuario,
       u.apellido,
       u.mail
FROM   pedido   ped
JOIN   usuario  u ON u.id_usuario = ped.id_usuario
WHERE  ped.eliminado = FALSE
  AND  u.eliminado   = FALSE
ORDER  BY ped.id_pedido;
```

Para verificar la vista una vez creada, el resultado de
`SELECT * FROM v_tp5_pedidos_usuario ORDER BY id_pedido`
debe ser idéntico al de la consulta manual anterior.

---

## Vista 3 — `v_tp5_detalle_pedido_productos`

### Objetivo de reporte
Proveer el detalle de líneas de pedido con el nombre del producto para
reportes de ventas e historial de compras. La regla central de esta vista
es preservar los detalles históricos aunque el producto haya sido eliminado
lógicamente: la venta ya ocurrió y el registro es parte del historial
inmutable de facturación. Un detalle vigente siempre debe mostrar el nombre
del producto aunque ese producto ya no esté en el catálogo activo.

### Tablas y JOINs
| Tabla | Rol | Condición de JOIN | Tipo |
|---|---|---|---|
| `detalle_pedido` | Tabla principal | — | — |
| `producto` | Tabla de referencia para el nombre | `producto.id_producto = detalle_pedido.id_producto` | INNER JOIN sin filtro de eliminado |

El JOIN con `producto` es `INNER` (la FK `id_producto NOT NULL` garantiza
que siempre existe una fila en `producto`), pero **no se aplica el filtro
`producto.eliminado = FALSE`**. Esto es intencional: el dato de nombre se
obtiene del registro de producto como fuente de descripción, pero la vigencia
del producto no condiciona la vigencia del detalle. La venta es un hecho
histórico independiente del estado actual del producto.

### Columnas expuestas
| Columna en la vista | Expresión de origen | Descripción |
|---|---|---|
| `id_detalle` | `detalle_pedido.id_detalle` | Identificador de la línea de detalle |
| `id_pedido` | `detalle_pedido.id_pedido` | FK al pedido padre |
| `id_producto` | `detalle_pedido.id_producto` | FK al producto (incluye eliminados) |
| `nombre_producto` | `producto.nombre_producto` | Nombre del producto en el momento del reporte |
| `cantidad` | `detalle_pedido.cantidad` | Unidades vendidas en esa línea |
| `precio_unitario` | `detalle_pedido.precio_unitario` | Precio snapshotteado por el trigger al momento de la venta |
| `subtotal` | `detalle_pedido.subtotal` | Subtotal calculado por trigger |

### Filtros de vigencia
- `detalle_pedido.eliminado = FALSE` — único filtro de vigencia aplicado.
  Excluye detalles dados de baja lógica (p. ej., líneas de pedidos cancelados
  que fueron marcadas como eliminadas).

**No se aplica `producto.eliminado = FALSE`.**
Esta es la diferencia de diseño más importante de esta vista respecto de
`v_pedido_detalle` (que tampoco lo filtra, pero no lo documenta
explícitamente). La ausencia del filtro es una decisión de negocio:
los registros de ventas deben conservarse íntegros para auditoría y
facturación, independientemente de si el producto sigue activo.

### Regla de seguridad
No aplica columnas sensibles. La vista no expone columnas de usuario
ni credenciales. El `precio_unitario` es el valor snapshotteado en el
momento de la venta (columna `detalle_pedido.precio_unitario`, completada
por `trg_subtotal`), no el precio actual del producto; esto es correcto
y debe preservarse.

### Consulta manual equivalente (para verificación posterior)
```sql
SELECT dp.id_detalle,
       dp.id_pedido,
       dp.id_producto,
       pr.nombre_producto,
       dp.cantidad,
       dp.precio_unitario,
       dp.subtotal
FROM   detalle_pedido dp
JOIN   producto       pr ON pr.id_producto = dp.id_producto
WHERE  dp.eliminado = FALSE
ORDER  BY dp.id_pedido, dp.id_detalle;
```

Para verificar la vista una vez creada, el resultado de
`SELECT * FROM v_tp5_detalle_pedido_productos ORDER BY id_pedido, id_detalle`
debe ser idéntico al de la consulta manual anterior.

Para verificar específicamente la regla de histórico, ejecutar:
```sql
-- Debe devolver filas: los detalles de productos eliminados (p. ej., id_producto IN (4, 16))
-- deben aparecer en la vista si el detalle mismo no está eliminado.
SELECT *
FROM   v_tp5_detalle_pedido_productos
WHERE  id_producto IN (
    SELECT id_producto FROM producto WHERE eliminado = TRUE
);
```
Si esta consulta devuelve cero filas, significa que la vista tiene un
filtro incorrecto sobre `producto.eliminado` y la implementación debe corregirse.
