# Especificaciones de Consultas — TP4 FoodStore Parte 3

---

## Especificación A: Ranking de productos por facturación dentro de su categoría (función de ventana)

### Objetivo
Listar todos los productos que tienen al menos una venta, mostrando cuántas unidades vendió cada uno y cuánto facturó, junto con su posición (puesto) dentro de la categoría a la que pertenece. El puesto se calcula por facturación descendente dentro de cada categoría, de modo que dos productos con igual facturación compartan el mismo puesto.

### Tablas involucradas
| Tabla | Rol |
|---|---|
| `categoria` | Fuente de nombre e id de categoría |
| `producto` | Fuente de nombre e id de producto; punto de unión entre categoría y detalles |
| `detalle_pedido` | Fuente de cantidades y subtotales; determina qué productos tienen ventas |

### Filtros obligatorios
- `categoria.eliminado = FALSE`
- `producto.eliminado = FALSE`
- `detalle_pedido.eliminado = FALSE`

Ningún filtro adicional sobre estado de pedido o fecha debe aplicarse salvo que se indique explícitamente.

### Columnas de salida
| Columna | Expresión | Descripción |
|---|---|---|
| `id_categoria` | `categoria.id_categoria` | Identificador de la categoría |
| `nombre_categoria` | `categoria.nombre_categoria` | Nombre de la categoría |
| `id_producto` | `producto.id_producto` | Identificador del producto |
| `nombre_producto` | `producto.nombre_producto` | Nombre del producto |
| `unidades_vendidas` | `SUM(detalle_pedido.cantidad)` | Total de unidades vendidas del producto |
| `facturacion` | `SUM(detalle_pedido.subtotal)` | Facturación total del producto |
| `puesto` | `RANK() OVER (...)` | Posición dentro de la categoría (ver ventana) |

No se permite usar `SELECT *`.

### Agrupación
`GROUP BY categoria.id_categoria, categoria.nombre_categoria, producto.id_producto, producto.nombre_producto`

Todas las columnas no agregadas deben estar presentes en el `GROUP BY`.

### Definición de la función de ventana
```
RANK() OVER (
    PARTITION BY categoria.id_categoria
    ORDER BY SUM(detalle_pedido.subtotal) DESC
)
```

- `PARTITION BY`: `categoria.id_categoria` — el ranking reinicia en cada categoría.
- `ORDER BY` dentro de la ventana: `SUM(detalle_pedido.subtotal) DESC` — mayor facturación obtiene puesto 1.
- Función: `RANK()` — los empates producen el mismo puesto y generan un salto en los puestos siguientes (comportamiento estándar de `RANK`, no `DENSE_RANK`).

### Regla de empate
Dos productos con exactamente el mismo valor de `SUM(detalle_pedido.subtotal)` dentro de la misma categoría reciben el mismo `puesto`. El siguiente puesto en esa categoría se incrementa en tantos como los empatados (ej.: dos productos en puesto 1 → el siguiente es puesto 3).

### Orden final del resultado
1. `id_categoria ASC` — agrupa visualmente los registros por categoría.
2. `puesto ASC` — dentro de cada categoría, del mejor al peor posicionado.
3. `id_producto ASC` — desempate visual entre productos con igual puesto; no afecta el valor de `puesto`.

### Criterios a preservar en versiones alternativas equivalentes
- La función de ventana debe ser `RANK`, no `DENSE_RANK` ni `ROW_NUMBER`.
- El `PARTITION BY` debe ser por `id_categoria`, no por nombre.
- El `ORDER BY` dentro de la ventana debe ser por facturación (`subtotal`), no por unidades.
- Los tres filtros de `eliminado` son obligatorios e independientes entre sí.
- Las métricas `unidades_vendidas` y `facturacion` deben calcularse como `SUM` sobre `detalle_pedido`, no derivarse de otras columnas.
- El orden final de tres niveles (categoría → puesto → id_producto) debe mantenerse.

---

## Especificación B: Pedidos cuyo total supera el promedio personal del usuario (subconsulta correlacionada)

### Objetivo
Identificar, para cada usuario, los pedidos individuales cuyo total es estrictamente mayor que el promedio de todos sus propios pedidos no eliminados. La comparación es siempre contra el promedio del mismo usuario, por lo que la subconsulta debe correlacionarse por `id_usuario`.

### Tablas involucradas
| Tabla | Rol |
|---|---|
| `usuario` | Fuente de identidad y nombre completo |
| `pedido` | Fuente de totales, fechas e id de pedido; tabla principal y tabla de la subconsulta |

### Filtros obligatorios
- Consulta principal: `pedido.eliminado = FALSE`
- Consulta principal: `usuario.eliminado = FALSE`
- Subconsulta correlacionada: `pedido.eliminado = FALSE` (debe repetirse explícitamente dentro de la subconsulta)

### Columnas de salida
| Columna | Expresión | Descripción |
|---|---|---|
| `id_usuario` | `usuario.id_usuario` | Identificador del usuario |
| `nombre_completo` | `usuario.nombre_usuario \|\| ' ' \|\| usuario.apellido` | Nombre y apellido concatenados |
| `id_pedido` | `pedido.id_pedido` | Identificador del pedido |
| `fecha` | `pedido.fecha` | Fecha del pedido |
| `total` | `pedido.total` | Total del pedido |
| `promedio_personal` | Resultado de la subconsulta | Promedio de totales del mismo usuario |

No se permite usar `SELECT *`.

### Correlación de la subconsulta
La subconsulta calcula `AVG(total)` sobre `pedido` filtrando por el mismo `id_usuario` de la fila evaluada en la consulta externa:

```
(
    SELECT AVG(p2.total)
    FROM pedido p2
    WHERE p2.id_usuario = <alias_externo>.id_usuario
      AND p2.eliminado = FALSE
)
```

- La subconsulta se re-evalúa por cada fila de la consulta externa.
- El alias de la tabla interna (`p2` o equivalente) debe diferenciarse del alias de la tabla externa para evitar ambigüedad.
- La condición de correlación es `p2.id_usuario = pedido_externo.id_usuario`.

### Condición de filtro principal
```
pedido.total > <subconsulta_promedio>
```

La comparación es **estrictamente mayor** (`>`); los pedidos iguales al promedio no deben incluirse.

### Agrupación
No se aplica `GROUP BY`. La consulta opera fila a fila sobre la unión de `usuario` y `pedido`.

### Orden final del resultado
1. `total DESC` — los pedidos más altos aparecen primero.
2. `id_pedido ASC` — desempate entre pedidos con igual total.

### Criterios a preservar en versiones alternativas equivalentes
- La subconsulta debe ser correlacionada (referencia al alias externo); no puede reemplazarse por un `JOIN` a una subconsulta de resumen no correlacionada a menos que produzca resultados idénticos fila a fila.
- El promedio debe calcularse únicamente sobre los pedidos no eliminados del mismo usuario (`eliminado = FALSE` dentro de la subconsulta).
- La comparación debe ser estricta (`>`), nunca `>=`.
- El nombre completo debe construirse concatenando `nombre_usuario` y `apellido`, no tomarse de una vista.
- Ambas tablas (`usuario` y `pedido`) deben filtrarse por `eliminado = FALSE` de forma independiente.
- No se permite exponer el `promedio_personal` redondeado en la cláusula de filtro; el redondeo solo puede aplicarse en la columna de salida si se indica como mejora visual.
- El orden de dos niveles (total descendente → id_pedido ascendente) debe mantenerse.
