# Plan de Indexado — TP5 FoodStore Parte A

> Este documento especifica las tres consultas seleccionadas para medir y optimizar con índices en la Parte A del TP5.
> No contiene `CREATE INDEX` ni DDL de ningún tipo.
> Su propósito es ser entregado a OpenCode para guiar la implementación y medición posterior.

---

## Antecedentes de TP3

Los índices creados y validados en TP3 son:

| Índice | Tabla | Estado |
|---|---|---|
| `idx_producto_id_categoria` | `producto (id_categoria)` | Existía en `schema.sql` |
| `idx_id_pedido_usuario` | `pedido (id_usuario)` | Existía en `schema.sql` |
| `idx_producto_nombre` | `producto (nombre_producto) WHERE eliminado = FALSE` | Existía en `schema.sql` |
| `idx_pedido_fecha` | `pedido (fecha)` | Existía en `schema.sql` |
| `idx_detalle_pedido_producto_vig` | `detalle_pedido (id_producto) WHERE eliminado = FALSE` | **Creado y aceptado en TP3** — mejora ~25x documentada |
| `idx_producto_cat_precio_disp_vig` | `producto (id_categoria, precio DESC) WHERE disponible = TRUE AND eliminado = FALSE` | **Creado y aceptado en TP3/TP4** — mejora ~8.6x documentada |

### Consulta cubierta por TP3 (no candidata para TP5)

**Productos sin ventas** (`queries.sql`, consulta E) ya está optimizada por
`idx_detalle_pedido_producto_vig`. El plan post-TP3 muestra Index Scan con
16.355 ms medidos. No se incluye como caso TP5 porque no existe índice nuevo
posible que aporte mejora adicional.

---

## Criterio de selección de consultas TP5

Las tres consultas deben cumplir simultáneamente:

1. Ejecutarse sobre `pedido` o `detalle_pedido` (tablas de mayor crecimiento).
2. Incluir al menos un predicado **selectivo** — filtro de punto o rango que
   reduzca significativamente las filas antes de la agregación o el JOIN.
3. No tener aún un índice que cubra ese predicado selectivo.
4. Hipótesis plausible de Seq Scan en ausencia del índice propuesto.

Las consultas de agregación global sin predicado de filtro (facturación por
mes, ranking de usuarios) **no son candidatas**: necesitan leer prácticamente
todas las filas de la tabla independientemente del índice, por lo que un
índice nuevo no reduciría el Seq Scan del nodo de acceso — solo desplazaría
el costo hacia otro nodo. Se documentan en la sección de propuestas
descartadas.

---

## Consulta 1 — Pedidos por estado y rango de fecha

### Origen
Variante mínima y justificada de `HU-PED-01` (`queries.sql`).
La consulta original lista todos los pedidos vigentes sin filtro;
aquí se agrega el filtro operativo más frecuente en producción:
estado concreto + ventana temporal reciente. Es la consulta que
ejecutaría cualquier panel de gestión para mostrar "pedidos confirmados
del último mes".

### Justificación de la variante
`queries.sql` no incluye un filtro combinado `estado + fecha`, pero la
estructura de `pedido` y los valores del ENUM `estado_pedido` hacen de
este patrón el caso de uso más frecuente del sistema. La variante agrega
exactamente dos predicados (`estado = ?` y `fecha >= ?`) sin modificar
joins ni proyección.

### SQL exacto a medir
```sql
SELECT ped.id_pedido,
       u.nombre_usuario || ' ' || u.apellido AS usuario,
       ped.fecha,
       ped.estado,
       ped.forma_pago,
       ped.total
FROM   pedido  ped
JOIN   usuario u ON u.id_usuario = ped.id_usuario
WHERE  ped.eliminado = FALSE
  AND  ped.estado    = 'CONFIRMADO'
  AND  ped.fecha     >= '2026-01-01'
ORDER  BY ped.fecha DESC;
```

### Tabla grande esperada
`pedido` — crece con cada orden; en producción acumula todos los
pedidos históricos y el filtro de estado + fecha recorta solo una
fracción de ellas.

### Predicados selectivos
- `ped.estado = 'CONFIRMADO'` — cardinalidad media-baja; en producción
  los pedidos CONFIRMADO representan una fracción de todos los estados.
- `ped.fecha >= '2026-01-01'` — rango temporal que excluye todo el
  historial anterior.
- Combinados, estos dos predicados son el par más selectivo disponible
  en `pedido` sin recurrir a la clave primaria.

### Índice existente que resulta insuficiente
`idx_pedido_fecha ON pedido (fecha)` cubre el predicado de rango sobre
`fecha`, pero no incluye `estado` ni `eliminado`. El planner deberá
leer todas las filas del rango temporal y luego descartar las que no
tienen `estado = 'CONFIRMADO'` y `eliminado = FALSE` (Rows Removed by
Filter). Con un historial largo, ese descarte puede ser costoso.

No existe índice que combine `(estado, fecha)` ni variante parcial
que incluya `eliminado = FALSE`.

### Hipótesis del índice nuevo
Un índice sobre `(estado, fecha DESC)` con condición parcial
`WHERE eliminado = FALSE` podría permitir al planner un Index Scan
o Bitmap Index Scan que satisfaga ambos predicados directamente,
reduciendo las filas leídas del heap y eliminando Rows Removed by
Filter. Esta es una hipótesis: si la fracción de pedidos con el
estado solicitado es alta o el rango temporal es amplio, el planner
podría igualmente preferir Seq Scan, y el índice se documentaría
como descartado.

### Criterio de aceptación
Se acepta si y solo si `EXPLAIN ANALYZE` muestra:
- Reducción medible del `Execution Time` (no solo del costo estimado).
- El nodo de acceso a `pedido` cambia a `Index Scan` o
  `Bitmap Index Scan` usando el índice nuevo.
- Desaparición o reducción de `Rows Removed by Filter` en ese nodo.

Si `EXPLAIN ANALYZE` no muestra mejora real, el índice se documenta
como descartado y se incluye la explicación del plan observado.

---

## Consulta 2 — Historial de pedidos de un usuario

### Origen
Variante mínima y justificada del patrón `v_pedidos_resumen` +
filtro por `id_usuario`, que corresponde a la vista definida en
`Objects.sql` y al caso de uso HU-PED-01 cuando un usuario consulta
su propio historial.

### Justificación de la variante
`queries.sql` lista todos los pedidos vigentes (HU-PED-01) sin filtrar
por usuario. La variante agrega `AND ped.id_usuario = ?`, que es el
predicado de punto más selectivo posible sobre `pedido` y representa
exactamente la consulta que se ejecuta en cada sesión de usuario
autenticado.

### SQL exacto a medir
```sql
SELECT ped.id_pedido,
       ped.fecha,
       ped.estado,
       ped.forma_pago,
       ped.total
FROM   pedido ped
WHERE  ped.id_usuario = 2
  AND  ped.eliminado  = FALSE
ORDER  BY ped.fecha DESC;
```

### Tabla grande esperada
`pedido` — en producción con miles de usuarios, la tabla crece
linealmente; un filtro por `id_usuario` devuelve solo los pedidos de
esa persona, que es una fracción pequeña del total.

### Predicados selectivos
- `ped.id_usuario = 2` — predicado de punto altamente selectivo;
  devuelve solo los pedidos de un usuario específico.
- `ped.eliminado = FALSE` — filtra lógicamente los pedidos borrados
  de ese usuario.

### Índice existente que resulta insuficiente
`idx_id_pedido_usuario ON pedido (id_usuario)` cubre el predicado
de punto, pero es un índice simple sin condición parcial: incluye
también las filas con `eliminado = TRUE`. El planner debe aplicar
el filtro `eliminado = FALSE` después del acceso por índice, generando
Rows Removed by Filter por cada pedido eliminado del usuario.

Adicionalmente, el índice no incluye `fecha`, por lo que el ORDER BY
`fecha DESC` requiere un Sort separado después del Index Scan.

### Hipótesis del índice nuevo
Un índice sobre `(id_usuario, fecha DESC)` con condición parcial
`WHERE eliminado = FALSE` podría:
1. Resolver el predicado de punto y el filtro de vigencia en un solo
   paso, eliminando Rows Removed by Filter.
2. Devolver las filas ya ordenadas por `fecha DESC`, evitando el nodo
   Sort.

Esta es una hipótesis: si el usuario tiene muy pocos pedidos eliminados,
la ganancia del índice parcial sobre el existente puede ser marginal
y el índice se documentaría como descartado.

### Criterio de aceptación
Se acepta si y solo si `EXPLAIN ANALYZE` muestra:
- Reducción medible del `Execution Time`.
- Desaparición del nodo `Sort` (plan con Index Scan en orden) o
  reducción comprobable del costo de Sort.
- Desaparición o reducción de `Rows Removed by Filter`.

Si la mejora no es medible, el índice se documenta como descartado.

---

## Consulta 3 — Pedidos cuyo total supera el promedio general

### Origen
Consulta D de `queries.sql`, tomada sin modificaciones.

### SQL exacto a medir
```sql
SELECT id_pedido,
       total
FROM   pedido
WHERE  eliminado = FALSE
  AND  total > (SELECT AVG(total) FROM pedido WHERE eliminado = FALSE)
ORDER  BY total DESC;
```

### Tabla grande esperada
`pedido` — la tabla se recorre dos veces: una para calcular el promedio
en la subconsulta y otra para filtrar por `total >` ese valor. Con un
volumen alto de pedidos, ambas pasadas son costosas sin índice.

### Predicados selectivos
- `total > <promedio>` — predicado de rango sobre `total`; en
  producción, aproximadamente la mitad de los pedidos supera el
  promedio (distribución dependiente de los datos), lo que lo hace
  selectivo en escenarios con distribución asimétrica (pedidos de alto
  valor que tiran el promedio hacia arriba).
- `eliminado = FALSE` — contexto de vigencia.

### Índice existente que resulta insuficiente
No existe ningún índice sobre `pedido.total`. El planner ejecuta
Seq Scan sobre `pedido` para la subconsulta del promedio y otro
Seq Scan (o reutiliza el mismo hash) para el filtro de la consulta
externa. Ambas pasadas son sin soporte de índice.

### Hipótesis del índice nuevo
Un índice sobre `(total DESC)` con condición parcial
`WHERE eliminado = FALSE` podría:
1. Permitir un Index Scan para la pasada de filtro (`total > promedio`),
   leyendo solo las filas del extremo superior del índice.
2. Devolver las filas ya en orden `total DESC`, eliminando el nodo Sort.

La subconsulta del promedio (`AVG(total)`) sigue requiriendo leer
todas las filas vigentes y probablemente no se beneficiará del índice
(el planner puede preferir Seq Scan para ese agregado). La mejora
esperada es principalmente en la pasada de filtro de la consulta
externa.

### Criterio de aceptación
Se acepta si y solo si `EXPLAIN ANALYZE` muestra:
- Reducción medible del `Execution Time` total.
- La consulta externa usa `Index Scan` sobre el índice nuevo en lugar
  de Seq Scan.
- Desaparición del nodo `Sort` en el plan de la consulta externa.

Si la mejora no es medible o el planner elige Seq Scan igualmente,
el índice se documenta como descartado.

---

## Propuestas descartadas

### 1. Índice sobre `pedido.eliminado`

**Definición rechazada:**
```
-- NO CREAR
CREATE INDEX idx_pedido_eliminado ON pedido (eliminado);
```

**Razón de rechazo — baja cardinalidad y costo de escritura.**

`eliminado` es un booleano: dos valores posibles. En un sistema
operativo normal, más del 95 % de los pedidos tienen `eliminado = FALSE`.
Un índice sobre esta columna sería prácticamente un índice sobre toda
la tabla, con los siguientes problemas:

1. **Sin selectividad**: el planner estima que si la fracción de filas
   devuelta supera el umbral de ~10–20 % (función de `random_page_cost`
   y `seq_page_cost`), el Seq Scan es más barato porque accede a las
   páginas en orden secuencial sin el overhead de recorrer el árbol
   B-tree.
2. **Heap fetch inevitable**: un índice sobre `eliminado` solo almacena
   el valor booleano; para obtener cualquier otra columna (`total`,
   `fecha`, etc.) el planner debe hacer un heap fetch por cada fila,
   resultando en el mismo número de accesos a disco que el Seq Scan
   pero con un paso extra.
3. **Costo de escritura**: cada INSERT y cada UPDATE sobre `pedido`
   debe mantener este índice, aumentando el costo de escritura sin
   ningún beneficio real en lectura.

El patrón correcto para columnas booleanas de vigencia es usarlas como
condición parcial (`WHERE eliminado = FALSE`) en un índice que incluya
además las columnas selectivas de la consulta
(como `idx_detalle_pedido_producto_vig` e
`idx_producto_cat_precio_disp_vig`).

---

### 2. Índice para consultas de agregación global sin filtro selectivo

Las consultas de `queries.sql` que agregan **todas** las filas vigentes
sin predicado de punto o rango no son candidatas para optimización con
índices:

- **Consulta B** — Facturación por categoría y mes: agrega toda la
  tabla `detalle_pedido` (`WHERE dp.eliminado = FALSE`) sin ningún
  filtro que reduzca el conjunto de filas antes de la agregación. Un
  índice parcial sobre `eliminado` no sería selectivo (ver punto 1
  anterior) y un índice sobre `id_pedido` ya está cubierto
  implícitamente por la FK. El planner necesita leer todas las filas
  para calcular el `SUM`; no hay índice que evite eso.

- **Consulta C** — Ranking de usuarios por gasto: agrega todos los
  pedidos vigentes de cada usuario (`WHERE ped.eliminado = FALSE`).
  La función de ventana `RANK()` requiere materializar el resultado
  completo del `GROUP BY` antes de ordenar, por lo que el Seq Scan
  sobre `pedido` es el plan correcto para esta consulta con los datos
  actuales. Un índice sobre `(id_usuario, total)` podría ser evaluado
  solo si la cátedra requiriese filtrar por usuario específico, lo
  cual convierte la consulta en la Consulta 2 de este plan.

Estas consultas pueden beneficiarse de otras técnicas (vistas
materializadas, tablas de resumen, particionado por fecha), pero no
de índices B-tree convencionales sobre la tabla base.
