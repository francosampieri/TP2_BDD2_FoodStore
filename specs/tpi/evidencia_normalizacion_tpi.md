# Evidencia de Normalización — TPI FoodStore

> Este documento especifica el contenido necesario para acreditar el criterio 3 del TPI
> (Normalización hasta 3FN/BCNF y dependencias funcionales) y sirve de base para la
> sección correspondiente del informe técnico integrador.
> No contiene SQL ejecutable ni modifica archivos existentes.

---

## Fuentes verificadas

| Archivo | Contenido relevante |
|---|---|
| `docs/modelo/informe_tp1_proyecto_foodstore.pdf` | Secciones "Modelo Relacional", "Normalización y Descomposición Relacional" y "Decisiones de Diseño" |
| `docs/modelo/modelo_er_foodstore.jpeg` | Diagrama ER con entidades, atributos y cardinalidades del diseño conceptual inicial |
| `sql/schema.sql` | Implementación final: tipos ENUM, tablas, CHECK, UNIQUE, FK, índices base |
| `sql/Objects.sql` | Triggers que justifican las columnas derivadas (`subtotal`, `total`) |

---

## 1. Dependencias funcionales del esquema final

Las dependencias se derivan del esquema implementado en `sql/schema.sql` y reflejan el estado post-TP2/TP3 (incluyendo soft delete y carga masiva).

### 1.1 `categoria`

```
id_categoria → nombre_categoria, descripcion_categoria, eliminado, created_at
```

- `id_categoria` es la única clave. No hay determinante alternativo con cardinalidad menor.
- `nombre_categoria` tiene restricción `UNIQUE` en schema, pero es un atributo, no una clave de diseño.

### 1.2 `producto`

```
id_producto → nombre_producto, precio, descripcion_producto, stock,
              imagen, disponible, id_categoria, eliminado, created_at
```

- `id_producto` es la única clave.
- `id_categoria` es FK hacia `categoria`; no determina ningún otro atributo de `producto`
  (el nombre de la categoría no está en `producto`, se accede por JOIN — esto es lo que garantiza 3FN).

### 1.3 `usuario`

```
id_usuario → nombre_usuario, apellido, mail, celular, contrasena, rol, eliminado, created_at
mail       → id_usuario   (determinante alternativo por restricción UNIQUE)
```

- Existen dos claves candidatas: `id_usuario` (surrogate, usada como PK) y `mail` (natural, única).
- Usar `id_usuario` como PK y mantener `mail` con `UNIQUE` respeta BCNF: ambas son superclaves.

### 1.4 `pedido`

```
id_pedido → fecha, estado, total, forma_pago, id_usuario, eliminado, created_at
```

- `id_pedido` es la única clave.
- `total` es un atributo derivado calculado por trigger; se discute en la sección 4.
- `id_usuario` es FK; no hay dependencia transitiva porque ningún otro atributo de `pedido`
  depende de datos del usuario (nombre, mail, etc. se obtienen por JOIN).

### 1.5 `detalle_pedido`

```
id_detalle              → cantidad, precio_unitario, subtotal, id_pedido, id_producto, eliminado, created_at
(id_pedido, id_producto) → id_detalle   (clave natural alternativa, garantizada por UNIQUE)
```

- Existen dos claves candidatas:
  - `id_detalle` (PK surrogate).
  - `(id_pedido, id_producto)` (clave natural compuesta, reforzada por `UNIQUE (id_pedido, id_producto)`).
- `precio_unitario` y `subtotal` son atributos de la línea de detalle, no del producto;
  se discuten en la sección 4.

---

## 2. Justificación de las formas normales

### Primera Forma Normal (1FN)

**Requisito:** atributos atómicos, sin grupos repetitivos, sin columnas multivaluadas.

**Cumplimiento:**
- Todos los atributos son escalares. No hay arrays ni columnas JSON de negocio en las
  tablas base (el JSONB de `sp_crear_pedido` es un parámetro de entrada, no una columna
  almacenada).
- Los ítems del pedido se modelan como filas individuales en `detalle_pedido` en lugar de
  un campo compuesto dentro de `pedido`. Esta descomposición es la que permite 1FN: si
  los productos fueran un array dentro de `pedido`, no se cumpliría.
- Cada tabla tiene PK definida (`BIGINT GENERATED ALWAYS AS IDENTITY`).

### Segunda Forma Normal (2FN)

**Requisito:** en 1FN y sin dependencias parciales (todo atributo no primo depende de la
clave completa, relevante cuando la PK es compuesta).

**Cumplimiento:**
- Las tablas `categoria`, `producto`, `usuario` y `pedido` tienen PK simple: la 2FN se
  cumple trivialmente.
- `detalle_pedido` tiene dos claves candidatas:
  - PK surrogate `id_detalle` — simple, sin dependencias parciales posibles.
  - Clave natural `(id_pedido, id_producto)` — compuesta. Los atributos no primos son
    `cantidad`, `precio_unitario` y `subtotal`, todos los cuales dependen de **ambas**
    columnas (una línea de detalle específica, no de `id_pedido` solo ni de `id_producto` solo).
    No hay dependencia parcial.

### Tercera Forma Normal (3FN)

**Requisito:** en 2FN y sin dependencias transitivas (ningún atributo no primo depende de
otro atributo no primo).

**Cumplimiento:**
- **`producto`**: `id_categoria` es FK, pero `nombre_categoria` **no existe** en `producto`.
  Se accede por JOIN. Si existiera, habría dependencia transitiva
  `id_producto → id_categoria → nombre_categoria`. Su ausencia es la decisión de diseño
  que garantiza 3FN.
- **`pedido`**: `id_usuario` es FK. Ningún dato del usuario (nombre, mail, rol) se almacena
  en `pedido`. Se accede por JOIN.
- **`detalle_pedido`**: `precio_unitario` podría parecer una dependencia transitiva
  (`id_detalle → id_producto → precio`), pero no lo es. Ver sección 4 para el argumento
  completo.
- **`pedido.total`**: podría parecer una dependencia transitiva calculada a partir de
  `detalle_pedido`. Ver sección 4.

### Forma Normal de Boyce-Codd (BCNF)

**Requisito:** para toda dependencia funcional no trivial X → Y, X debe ser superclave.

**Cumplimiento en las relaciones base:**
- En `categoria`, `producto`, `pedido` y `detalle_pedido`, el único determinante no
  trivial de los atributos de negocio es la clave candidata de la tabla.
- En `usuario`, `mail` es un segundo determinante. `mail → id_usuario` cumple BCNF
  porque `mail` es superclave (la restricción `UNIQUE` garantiza que identifica
  unívocamente cada fila).
- En `detalle_pedido`, `(id_pedido, id_producto)` determina `id_detalle` y todos los
  demás atributos. Es superclave por `UNIQUE (id_pedido, id_producto)`. Cumple BCNF.

**Nota sobre `subtotal` y `total`:** estas columnas son valores derivados mantenidos
por triggers (`trg_subtotal` y `trg_total_ins`/`trg_total_upd`). Técnicamente
introducen dependencias funcionales transitivas dentro de sus respectivas tablas
(`id_detalle → cantidad, precio_unitario → subtotal`). Se trata de una
**desnormalización controlada por regla de negocio**, no de una violación de BCNF
en el modelo conceptual: la consistencia está garantizada por el motor (los triggers
son `BEFORE INSERT OR UPDATE`) y los valores nunca se asignan manualmente en los DML
de la aplicación. La justificación detallada está en la sección 4.

---

## 3. `detalle_pedido` como resolución de la relación N:M

### El problema que resuelve

La relación entre `pedido` y `producto` es de muchos a muchos:
- Un pedido puede contener muchos productos.
- Un producto puede aparecer en muchos pedidos.

No es posible representar esta relación directamente en el modelo relacional sin
redundancia o pérdida de información: si se almacenara una lista de productos dentro
de `pedido`, se violaría 1FN; si se almacenara un pedido dentro de `producto`, también.

### La solución: tabla de intersección con atributos propios

`detalle_pedido` resuelve la N:M introduciendo una entidad intermedia con identidad propia
(`id_detalle`) y atributos que pertenecen a la relación, no a ninguna de las entidades solas:

| Atributo | Pertenece a |
|---|---|
| `cantidad` | A la relación: cuántas unidades de ese producto en ese pedido |
| `precio_unitario` | A la relación: el precio capturado al momento de ese pedido (incorporado en la implementación) |
| `subtotal` | A la relación: el importe de esa línea |

Ninguno de estos atributos puede existir en `pedido` solo ni en `producto` solo sin
redundancia. Pertenecen exclusivamente al par `(id_pedido, id_producto)`.

### Restricción de unicidad

`UNIQUE (id_pedido, id_producto)` en `detalle_pedido` garantiza que el mismo producto
no puede aparecer dos veces en el mismo pedido. Esta restricción refuerza la semántica
de la relación M:N y permite tratar `(id_pedido, id_producto)` como clave natural
alternativa.

---

## 4. Justificación de `precio_unitario`, `subtotal` y `pedido.total`

### 4.1 `precio_unitario` — captura histórica del precio (incorporado en la implementación)

`precio_unitario` no estaba en el ER inicial de `DETALLE_PEDIDO`. Se incorporó en
`schema.sql` como decisión de diseño de la implementación. Almacena el precio del
producto **en el momento en que se creó la línea de detalle**. El trigger `trg_subtotal`
(`BEFORE INSERT OR UPDATE` en `detalle_pedido`, definido en `sql/Objects.sql`) lo
captura automáticamente:

```
IF NEW.precio_unitario IS NULL THEN
    SELECT precio INTO NEW.precio_unitario
    FROM producto WHERE id_producto = NEW.id_producto;
END IF;
```

**Por qué no viola 3FN:**
Una dependencia transitiva sería `id_detalle → id_producto → precio` si y solo si
`precio_unitario` fuera siempre igual al precio actual de `producto`. No lo es.
`producto.precio` puede cambiar después de la venta. `precio_unitario` es el precio
**en el momento histórico de la transacción**, un dato que ya no puede derivarse de
ninguna otra columna de la base una vez que el precio del producto cambió. Es un hecho
inmutable del registro contable, no redundancia.

**Consecuencia de diseño:** si `precio_unitario` se eliminara y se derivara
dinámicamente de `producto.precio`, las consultas de historial de ventas devolverían
importes incorrectos para todos los pedidos anteriores al último cambio de precio.
Esto no es aceptable para un sistema de facturación.

### 4.2 `subtotal` — desnormalización controlada por trigger

`detalle_pedido.subtotal = cantidad × precio_unitario`.

Técnicamente es un valor derivado: podría calcularse en cada consulta. Su almacenamiento
introduce una dependencia `id_detalle → subtotal` que es transitiva en términos estrictos
(`id_detalle → cantidad, precio_unitario → subtotal`).

**Por qué es una desnormalización controlada y no una anomalía:**

1. **Atomicidad:** el trigger `trg_subtotal` garantiza que `subtotal` siempre es consistente
   con `cantidad` y `precio_unitario`. No hay riesgo de inconsistencia por escritura manual:
   la columna es calculada automáticamente en `BEFORE INSERT OR UPDATE`.
2. **Rendimiento:** las consultas analíticas (facturación por categoría y mes, top 5 productos,
   ranking de usuarios) agregan `SUM(subtotal)` sobre cientos de miles de filas. Calcular
   `SUM(cantidad * precio_unitario)` en cada consulta introduce una operación aritmética
   por fila en el nodo de agregación. Con `subtotal` precalculado, la consulta solo suma.
3. **Precedente académico:** la normalización estricta recomienda no almacenar valores
   derivados, pero PostgreSQL y la literatura de bases de datos de producción reconocen que
   las columnas derivadas mantenidas por triggers son un mecanismo válido cuando la
   consistencia está garantizada por el motor.

### 4.3 `pedido.total` — agregado mantenido por trigger de sentencia

`pedido.total = SUM(detalle_pedido.subtotal)` para los detalles no eliminados del pedido.

Técnicamente también es un valor derivado. Su almacenamiento responde a las mismas
razones que `subtotal`, con una consideración adicional:

- Los triggers `trg_total_ins` y `trg_total_upd` (`AFTER INSERT/UPDATE`, statement-level,
  con Transition Tables `REFERENCING NEW TABLE AS afectados`) recalculan `total` para
  todos los pedidos afectados en una sola sentencia. Son los triggers más complejos del
  proyecto y su propósito es exactamente mantener este dato consistente.
- Sin `pedido.total`, la vista `v_pedidos_resumen` necesitaría una subconsulta agregada
  por cada pedido para mostrar el total, lo que haría la vista no escalable con cientos
  de miles de pedidos.

**Conclusión sobre las desnormalizaciones:** tanto `subtotal` como `total` son
desnormalizaciones intencionales, documentadas y controladas por triggers. El sistema
garantiza su consistencia de forma automática y no expone la escritura directa de estas
columnas al usuario (los DML de datos no las informan; `data.sql` y `queries.sql`
no las incluyen en los INSERT). Son equivalentes a columnas calculadas persistidas,
patrón reconocido en sistemas RDBMS de producción.

---

## 5. Evolución entre el ER inicial y `schema.sql`

### 5.1 Principio general

`docs/modelo/modelo_er_foodstore.jpeg` representa el **diseño conceptual inicial** del proyecto:
entidades, atributos y cardinalidades. `sql/schema.sql` es la **implementación final**,
que concreta ese diseño con tipos precisos, restricciones de valor y reglas de integridad
referencial.

La transición es fiel al diseño: todos los atributos del ER están presentes en schema.sql.
La única incorporación de atributo de negocio entre el ER y la implementación es
`precio_unitario` en `detalle_pedido` (ver sección 5.2).

### 5.2 Único atributo incorporado en la implementación: `precio_unitario`

El ER inicial de `DETALLE_PEDIDO` no incluye `precio_unitario`. Su incorporación en
`schema.sql` responde a una decisión de negocio adoptada en la implementación:

**Justificación como snapshot histórico:**
`precio_unitario` almacena el precio del producto en el momento exacto en que se registró
la línea de detalle. `producto.precio` puede cambiar después de la venta; sin este campo,
el historial de facturación devolvería importes incorrectos para todas las ventas
anteriores a cada actualización de precio. Es un hecho inmutable de la transacción, no
redundancia calculable.

El trigger `trg_subtotal` (`BEFORE INSERT OR UPDATE` en `detalle_pedido`) lo captura
automáticamente desde `producto.precio` si no se informa en el INSERT:

```
IF NEW.precio_unitario IS NULL THEN
    SELECT precio INTO NEW.precio_unitario
    FROM producto WHERE id_producto = NEW.id_producto;
END IF;
```

Una vez insertado, el valor permanece desacoplado de `producto.precio`.

**Nota sobre `id_detalle`:** el ER ya muestra `id_detalle` como PK de `DETALLE_PEDIDO`.
`schema.sql` la implementa como `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`.
La clave natural `(id_pedido, id_producto)` se preserva mediante
`UNIQUE (id_pedido, id_producto)`, que coexiste con la PK surrogate. No hubo cambio
de PK entre ER e implementación.

### 5.3 Diferencias de nombre (convenciones del proyecto)

| ER | schema.sql | Regla aplicada |
|---|---|---|
| `nombre` (en USUARIO) | `nombre_usuario` | Prefijo de tabla para evitar ambigüedad en JOINs |
| `descripcion` (en CATEGORIA) | `descripcion_categoria` | Ídem |
| `descripcion` (en PRODUCTO) | `descripcion_producto` | Ídem |

### 5.4 Diferencias de tipo (decisiones de implementación en PostgreSQL)

| ER | schema.sql | Razón |
|---|---|---|
| `rol` como texto `ADMIN/USUARIO` | `CREATE TYPE rol AS ENUM ('ADMIN','USUARIO')` | Restricción de dominio a nivel de motor; más estricto que CHECK sobre VARCHAR |
| `estado` como texto | `CREATE TYPE estado_pedido AS ENUM (...)` | Ídem |
| `forma_pago` como texto | `CREATE TYPE forma_pago AS ENUM (...)` | Ídem |
| PK genérica | `BIGINT GENERATED ALWAYS AS IDENTITY` | PostgreSQL moderno; no usa SERIAL (deprecated) |
| `precio` sin precisión | `NUMERIC(10,2)` | Precisión monetaria explícita |
| `total` sin precisión | `NUMERIC(12,2)` | Mayor rango para acumulados de pedido |

### 5.5 Restricciones de valor y referencias no representadas en el ER

Los diagramas ER no suelen incluir restricciones de valor ni semántica de FK. Estas
se formalizaron en `schema.sql`:

- `CHECK (precio >= 0)`, `CHECK (stock >= 0)`, `CHECK (total >= 0)`, `CHECK (subtotal >= 0)`,
  `CHECK (precio_unitario >= 0)`, `CHECK (cantidad > 0)`.
- `UNIQUE (usuario.mail)`, `UNIQUE (categoria.nombre_categoria)`.
- `UNIQUE (id_pedido, id_producto)` en `detalle_pedido`: formaliza la clave natural
  del ER como restricción explícita.
- `ON DELETE RESTRICT` en `detalle_pedido.id_pedido`: impide borrar físicamente un pedido
  con detalles. El borrado lógico con `eliminado` es el mecanismo previsto.
- `DEFAULT CURRENT_DATE` en `pedido.fecha`, `DEFAULT 'PENDIENTE'` en `pedido.estado`,
  `DEFAULT 0` en `pedido.total`, `DEFAULT TRUE` en `producto.disponible`: valores por
  defecto operativos que simplifican los INSERT.

---

## 6. Esquema para `docs/tpi/informe_tpi_parcial.md`

El siguiente esquema de secciones cubre los nueve criterios evaluativos del TPI. Cada
sección indica qué archivos del repositorio la respaldan y qué elementos concretos deben
citarse.

---

### Sección 1 — Introducción y alcance

**Criterio cubierto:** contexto general.

- Descripción del dominio: sistema de pedidos gastronómicos.
- Tecnología: PostgreSQL 17, sin capa de aplicación. Toda la lógica vive en la base.
- Bases de trabajo usadas a lo largo del proyecto: `foodstore`, `foodstore_tp2`,
  `foodstore_tp3`, `foodstore_tp5`.

---

### Sección 2 — Modelo ER y diseño conceptual

**Criterios cubiertos:** 1 (Modelo ER), 2 (paso ER → relacional).

**Citar:**
- `docs/modelo/modelo_er_foodstore.jpeg` — diagrama con las cinco entidades y sus relaciones.
- Tabla de entidades, atributos y cardinalidades.
- Explicación de la relación M:N `pedido–producto` resuelta por `detalle_pedido`.
- Nota sobre evolución: el ER es el diseño conceptual; `schema.sql` es la implementación
  final. La única incorporación de atributo de negocio entre ambos es `precio_unitario`
  en `detalle_pedido`. Los demás cambios son de tipo, precisión, restricciones y defaults.

---

### Sección 3 — Modelo relacional y normalización

**Criterio cubierto:** 3 (Normalización 3FN/BCNF y dependencias funcionales).

**Citar:**
- `docs/modelo/informe_tp1_proyecto_foodstore.pdf` — secciones "Modelo Relacional" y
  "Normalización y Descomposición Relacional".
- Lista completa de dependencias funcionales por tabla (sección 1 de este documento).
- Justificación de 1FN, 2FN, 3FN y BCNF (sección 2 de este documento).
- Argumento de `precio_unitario` como snapshot histórico, no redundancia (sección 4.1).
- Argumento de `subtotal` y `total` como desnormalizaciones controladas (secciones 4.2–4.3).

---

### Sección 4 — DDL: implementación del esquema

**Criterio cubierto:** 4 (DDL completo).

**Citar:**
- `sql/schema.sql` — ENUMs, tablas, PK, FK, CHECK, UNIQUE, NOT NULL, índices base.
- Tabla de tipos ENUM con sus valores.
- Tabla consolidada de todos los índices del proyecto:

| Índice | Tabla | Clave | Condición parcial | Origen | Mejora medida |
|---|---|---|---|---|---|
| `idx_producto_id_categoria` | `producto` | `(id_categoria)` | ninguna | `schema.sql` | — |
| `idx_id_pedido_usuario` | `pedido` | `(id_usuario)` | ninguna | `schema.sql` | — |
| `idx_producto_nombre` | `producto` | `(nombre_producto)` | `eliminado = FALSE` | `schema.sql` | — |
| `idx_pedido_fecha` | `pedido` | `(fecha)` | ninguna | `schema.sql` | — |
| `idx_detalle_pedido_producto_vig` | `detalle_pedido` | `(id_producto)` | `eliminado = FALSE` | TP3 | ~25x (406→16 ms) |
| `idx_producto_cat_precio_disp_vig` | `producto` | `(id_categoria, precio DESC)` | `disponible=TRUE AND eliminado=FALSE` | TP3/TP4 | ~8.6x (93→11 ms) |
| `idx_pedido_cancelado_fecha_vig` | `pedido` | `(fecha DESC)` | `eliminado=FALSE AND estado='CANCELADO'` | TP5 | ~74.7x (211→3 ms) |
| `idx_producto_no_disponible_nombre_vig` | `producto` | `(nombre_producto ASC)` | `eliminado=FALSE AND disponible=FALSE` | TP5 | ~11.4x (32→3 ms) |
| `idx_detalle_cantidad_excepcional_vig` | `detalle_pedido` | `(cantidad DESC, id_detalle ASC)` | `eliminado=FALSE AND cantidad>=5` | TP5 | ~122x (183→2 ms) |
| `uq_mv_tp5_facturacion_categoria_mes` | `mv_tp5_facturacion_categoria_mes` | `(id_categoria, mes)` | ninguna | TP5 | habilita REFRESH CONCURRENTLY |

- Justificación de `ON DELETE RESTRICT` en `detalle_pedido.id_pedido`.

---

### Sección 5 — DML y consultas

**Criterio cubierto:** 5 (JOIN, agregación, subconsultas, GROUP BY/HAVING, ventana).

**Citar:**
- `sql/queries.sql` — 5 epics (HU-CAT, HU-PROD, HU-USR, HU-PED) y consultas A–E:
  - A: `SUM + GROUP BY + LIMIT` — top 5 productos más vendidos.
  - B: `SUM + GROUP BY + date_trunc` — facturación mensual por categoría.
  - C: `RANK() OVER (ORDER BY SUM(...) DESC)` — función de ventana.
  - D: subconsulta escalar en `WHERE` — pedidos sobre el promedio general.
  - E: `LEFT JOIN ... WHERE IS NULL` — anti-join para productos sin ventas.
- `sql/consultas_parte3_tp4.sql`:
  - Spec A: `RANK() OVER (PARTITION BY id_categoria ...)` — ventana particionada.
  - Spec B: subconsulta correlacionada por `id_usuario`.
- **Ejemplo de `HAVING`** — verificación V2 en `sql/carga_masiva_tp3.sql`:
  ```sql
  SELECT id_pedido, count(*) AS n
  FROM   detalle_pedido
  WHERE  id_pedido IN (SELECT id_pedido FROM tmp_tp3_pedidos)
  GROUP  BY id_pedido
  HAVING count(*) <> 2;
  ```
  Esta consulta usa `HAVING` para detectar pedidos que no tienen exactamente dos detalles.
  Es el único ejemplo de `HAVING` en el repositorio; debe citarse explícitamente.
- Equivalencias verificadas con `EXCEPT` en ambas direcciones: TP3 Parte 4 (0 filas ×4)
  y TP4 Parte 3 (0 filas ×4).

---

### Sección 6 — Vistas, funciones y procedimiento almacenado

**Criterio cubierto:** 6 (Vistas, funciones, PL/pgSQL).

**Citar:**
- `sql/Objects.sql` — tabla de objetos programáticos:
  - Vistas: `v_productos_vigentes`, `v_pedidos_resumen`, `v_pedido_detalle`, `v_categorias_vigentes`.
  - Función SQL STABLE: `calcular_total_pedido(BIGINT)`.
  - Funciones PL/pgSQL de trigger: `fn_set_subtotal`, `fn_recalcular_total`.
  - Procedimiento: `sp_crear_pedido(BIGINT, forma_pago, JSONB)`.
- `sql/views_tp5.sql` — vistas TP5: `v_tp5_productos_categoria`, `v_tp5_pedidos_usuario`,
  `v_tp5_detalle_pedido_productos` (con regla de histórico documentada).
- `sql/vista_materializada_tp5.sql` — `mv_tp5_facturacion_categoria_mes` con índice único.
  Medición: consulta directa 706 ms → lectura de vista 0.284 ms.
- `sql/restricciones.sql` — funciones PL/pgSQL de restricción:
  `fn_check_estado_transition`, `fn_check_categoria_baja_logica`.

---

### Sección 7 — Reglas de negocio y triggers

**Criterio cubierto:** 7 (CHECK, UNIQUE, triggers).

**Citar:**
- `sql/schema.sql` — restricciones CHECK y UNIQUE.
- `sql/Objects.sql` — triggers de cálculo (`trg_subtotal`, `trg_total_ins`, `trg_total_upd`).
  Destacar uso de Transition Tables (`REFERENCING NEW TABLE AS afectados`) para eficiencia.
- `sql/restricciones.sql` — triggers de integridad:
  - `trg_check_estado_transition`: máquina de estados del pedido.
  - `trg_check_categoria_baja_logica`: impide dar de baja categorías con productos vigentes.
- `sql/test_restricciones.sql` y `docs/tp2/duia_parte1.md` — 14 casos de prueba, todos con resultado
  real documentado.
- Tabla de transiciones válidas del pedido:

```
PENDIENTE  → CONFIRMADO  ✓
PENDIENTE  → CANCELADO   ✓
CONFIRMADO → TERMINADO   ✓
CONFIRMADO → CANCELADO   ✓
TERMINADO  → cualquier estado  ✗ (estado final)
CANCELADO  → cualquier estado  ✗ (estado final)
```

---

### Sección 8 — Transacciones, aislamiento y concurrencia

**Criterio cubierto:** 8 (atomicidad, COMMIT, ROLLBACK, aislamiento, concurrencia).

**Citar:**
- `sql/transacciones.sql` — cuatro escenarios con resultado esperado:
  1. Atomicidad de `sp_crear_pedido` (producto inexistente → ROLLBACK implícito).
  2. `BEGIN/COMMIT` vs. `BEGIN/ROLLBACK` sobre stock.
  3. Lectura no repetible: `READ COMMITTED` vs. `SERIALIZABLE` (requiere 2 sesiones).
  4. Sobreventa sin control (demostración del problema) vs. solución con `FOR UPDATE`.
- `docs/tp2/informe_concurrencia.md` — análisis de niveles de aislamiento.
- `sql/carga_masiva_tp3.sql` — `BEGIN` explícito sin COMMIT automático; el usuario decide
  manualmente según el resultado de las verificaciones V1–V7.
- Aclarar que `sp_crear_pedido` no contiene `COMMIT` explícito: el llamador es responsable
  de la transacción envolvente; los `RAISE EXCEPTION` internos abortan la transacción activa.

---

### Sección 9 — Soft delete y optimización

**Criterios cubiertos:** 9 (soft delete) y 4 parcial (índices, resultados antes/después).

**Citar:**
- Patrón `eliminado BOOLEAN NOT NULL DEFAULT FALSE` en las 5 tablas.
- Diferencias de filtro entre vistas de `Objects.sql` y vistas TP5:
  - `v_pedidos_resumen` filtra solo `pedido.eliminado`, no `usuario.eliminado`.
  - `v_tp5_pedidos_usuario` filtra ambas tablas.
  - `v_tp5_detalle_pedido_productos` no filtra `producto.eliminado` por diseño (histórico).
- Índices parciales `WHERE eliminado = FALSE` como patrón correcto.
- Propuesta descartada `ON pedido (eliminado)`: baja cardinalidad, nunca elegido por planner.
- **Resultados de optimización antes/después** (tabla consolidada — fuentes: `docs/tp3/informe_tp3.md`,
  `docs/tp4/informe_tp4.md`, `docs/tp5/informe_mediciones_tp5.md`):

| Consulta | Execution Time antes | Execution Time después | Mejora |
|---|---|---|---|
| Q3 TP3: detalle por producto | 406.794 ms | 16.355 ms | ~25x |
| Competencia TP3/TP4: productos por categoría y precio | 93.394 ms | 10.855 ms | ~8.6x |
| TP5-1: pedidos cancelados | 210.677 ms | 2.822 ms | ~74.7x |
| TP5-2: productos no disponibles | 31.581 ms | 2.767 ms | ~11.4x |
| TP5-3: detalles con cantidad >= 5 | 182.874 ms | 1.498 ms | ~122x |
| Vista materializada: facturación mensual | 706.310 ms | 0.284 ms | ~2489x |

---

### Sección 10 — Herramientas de IA y decisiones

**No es un criterio de normalización, pero es requerido por el TPI.**

**Citar:** `docs/tp2/duia_parte1.md`, `docs/tp3/duia_tp3.md`, `docs/tp4/duia_tp4.md`, `docs/tp5/duia_tp5.md`.

**Elementos a incluir por cada DUIA:**
- Herramienta utilizada (OpenCode / Kiro) y para qué tarea concreta.
- Qué se aceptó sin modificaciones.
- Qué se descartó o corrigió y por qué (con evidencia real cuando aplica).

**Ejemplos de decisiones descartadas con evidencia:**
- Índices Q1 y Q2 en TP3: propuestos por OpenCode, descartados por Execution Time
  (7→57 ms y 182→289 ms respectivamente).
- Reescrituras de TP4 Parte 1: descartadas por tiempo real (facturación 946→1089 ms,
  ranking 1283→2599 ms).
- Afirmación sobre paralelismo en TP3 Parte 3: rechazada; el plan fue serial.
- Afirmación sobre `Parallel Hash` en TP4 Parte 2: corregida (no es `Hash` simple).

---

### Sección 11 — Conclusiones

- Síntesis de lo implementado y verificado con evidencia real.
- Limitaciones: las mediciones dependen de la carga de la base de trabajo; los tiempos
  no son reproducibles exactamente en otra máquina.
- Posibles extensiones: particionado por fecha en `pedido` y `detalle_pedido`,
  política de REFRESH programada para la vista materializada.

