# Auditoría TPI Parcial — FoodStore

> Auditoría de la primera entrega parcial del Trabajo Práctico Integrador
> frente a nueve criterios evaluativos. Basada en la lectura completa del
> repositorio: `sql/`, archivos de informe, DUIAs y docs de diseño.
> No contiene SQL, no modifica archivos existentes y no genera commits.

---

## Resumen ejecutivo

| # | Criterio | Estado |
|---|---|---|
| 1 | Modelo ER | **Cubierto** |
| 2 | Paso ER → relacional, relaciones 1:N y N:M | **Cubierto** |
| 3 | Normalización 3FN/BCNF y dependencias funcionales | **Parcial** |
| 4 | DDL completo: tipos, PK, FK, restricciones, índices | **Cubierto** |
| 5 | DML y consultas: JOIN, agregación, subconsultas, GROUP BY/HAVING, ventana | **Cubierto** |
| 6 | Vistas, funciones y procedimientos PL/pgSQL | **Cubierto** |
| 7 | Reglas de negocio: CHECK, UNIQUE, triggers | **Cubierto** |
| 8 | Transacciones: atomicidad, COMMIT, ROLLBACK, aislamiento, concurrencia | **Cubierto** |
| 9 | Soft delete y su impacto en consultas e índices | **Cubierto** |

---

## Criterio 1 — Modelo ER

**Estado: Cubierto**

### Evidencia disponible
- `docs/modelo_er_foodstore.jpeg` — diagrama ER original con entidades,
  atributos y cardinalidades.
- `docs/informe_tp1_proyecto_foodstore.pdf` — informe TP1 que describe
  el diseño inicial del modelo.

### Qué debe explicarse o citarse en el informe TPI
- Citar el diagrama ER como punto de partida del diseño y referenciarlo
  visualmente en la sección de modelado.
- Mencionar las cinco entidades principales: `categoria`, `producto`,
  `usuario`, `pedido`, `detalle_pedido`.
- Describir las cardinalidades: `categoria` 1:N `producto`,
  `usuario` 1:N `pedido`, `pedido` 1:N `detalle_pedido`,
  `producto` referenciado desde `detalle_pedido` (N:M resuelta).
- Documentar la evolución mínima entre el ER original y el esquema
  final: la incorporación de `created_at TIMESTAMPTZ` en todas las
  tablas y la columna `imagen` en `producto` no aparecen en el ER
  inicial y representan decisiones de implementación posteriores;
  tratarlas como evolución del diseño, no como error.

### Pendiente documental
Ninguno. El diagrama y el informe TP1 cubren el criterio.

---

## Criterio 2 — Paso ER → Modelo Relacional, relaciones 1:N y N:M

**Estado: Cubierto**

### Evidencia disponible
- `sql/schema.sql` — implementación final de las cinco tablas con
  sus claves primarias, foráneas y restricciones.
- `docs/informe_tp1_proyecto_foodstore.pdf` — documentación del paso
  de ER a relacional.

### Qué debe explicarse o citarse en el informe TPI
- **Relaciones 1:N implementadas:**
  - `categoria (1) → producto (N)`: FK `producto.id_categoria REFERENCES categoria(id_categoria)`.
  - `usuario (1) → pedido (N)`: FK `pedido.id_usuario REFERENCES usuario(id_usuario)`.
  - `pedido (1) → detalle_pedido (N)`: FK `detalle_pedido.id_pedido REFERENCES pedido(id_pedido) ON DELETE RESTRICT`.
- **Relación N:M resuelta:** la relación muchos-a-muchos entre `pedido`
  y `producto` se resolvió mediante la tabla de intersección
  `detalle_pedido`, que agrega atributos propios: `cantidad`,
  `precio_unitario` (snapshot del precio al momento de la venta),
  `subtotal` y la restricción `UNIQUE (id_pedido, id_producto)`.
- Destacar que `ON DELETE RESTRICT` en `detalle_pedido.id_pedido`
  impide borrar físicamente un pedido que tenga detalles: el borrado
  lógico con `eliminado` es el mecanismo previsto.
- Mencionar la restricción `UNIQUE (id_pedido, id_producto)` como
  regla de negocio que impide registrar el mismo producto dos veces
  en el mismo pedido.

### Pendiente documental
Ninguno.

---

## Criterio 3 — Normalización hasta 3FN/BCNF y dependencias funcionales

**Estado: Parcial**

### Evidencia disponible
- `docs/informe_tp1_proyecto_foodstore.pdf` — contiene análisis de
  normalización inicial.
- `sql/schema.sql` — el esquema implementado evidencia las decisiones
  de normalización (no hay columnas calculadas redundantes excepto las
  gestionadas por triggers).

### Qué debe explicarse o citarse en el informe TPI
- Enumerar las dependencias funcionales de cada tabla:
  - `producto`: `id_producto → nombre_producto, precio, stock, disponible, descripcion_producto, imagen, id_categoria, eliminado, created_at`
  - `detalle_pedido`: `(id_pedido, id_producto) → cantidad, precio_unitario, subtotal`
    — la clave compuesta funcional está reforzada por `UNIQUE (id_pedido, id_producto)`.
  - `pedido`: `id_pedido → fecha, estado, total, forma_pago, id_usuario, eliminado`
- Argumentar que cada tabla está en 3FN/BCNF:
  - No hay dependencias transitivas: `producto.nombre_categoria` no
    existe (la categoría se resuelve por JOIN).
  - `detalle_pedido.precio_unitario` es un snapshot intencional, no
    una dependencia transitiva: el precio actual del producto puede
    cambiar sin afectar los detalles históricos.
  - `pedido.total` es una columna derivada mantenida por trigger,
    no una violación de normalización: su presencia está justificada
    por rendimiento y atomicidad transaccional.

### Qué falta o es insuficiente
- El informe TP1 documenta la normalización inicial, pero **no existe
  un documento explícito en el repositorio que liste las dependencias
  funcionales del esquema final** (post-carga masiva y restricciones
  de TP2/TP3). El informe TPI debe incluir esta sección con las
  dependencias del esquema en `schema.sql`.
- Justificar explícitamente por qué `precio_unitario` en
  `detalle_pedido` no viola 3FN (snapshot vs. redundancia calculable).

### Mínimo necesario para completar el criterio
Una sección de una página en el informe TPI que liste las dependencias
funcionales por tabla y argumente la 3FN/BCNF del esquema final.

---

## Criterio 4 — DDL completo: tipos, PK, FK, restricciones e índices

**Estado: Cubierto**

### Evidencia disponible
- `sql/schema.sql`:
  - Tres tipos ENUM: `rol`, `estado_pedido`, `forma_pago`.
  - Cinco tablas con `BIGINT GENERATED ALWAYS AS IDENTITY` como PK.
  - FK con `REFERENCES` y `ON DELETE RESTRICT` donde corresponde.
  - `CHECK`: `precio >= 0`, `stock >= 0`, `subtotal >= 0`,
    `precio_unitario >= 0`, `total >= 0`, `cantidad > 0`.
  - `NOT NULL` en todas las columnas obligatorias.
  - `UNIQUE`: `usuario.mail`, `categoria.nombre_categoria`,
    `(id_pedido, id_producto)` en `detalle_pedido`.
  - Cuatro índices base: `idx_producto_id_categoria`,
    `idx_id_pedido_usuario`, `idx_producto_nombre`,
    `idx_pedido_fecha`.
- `sql/indices_optimizacion_tp3.sql`: índice `idx_detalle_pedido_producto_vig` aceptado por evidencia real (~25x).
- `sql/competencia_optimizacion_tp3.sql` y `sql/competencia_tp4.sql`:
  índice `idx_producto_cat_precio_disp_vig` aceptado (~8.6x).
- `sql/indices_tp5.sql`: tres índices parciales aceptados por
  evidencia real (74.7x, 11.4x, 122x).

### Qué debe explicarse o citarse en el informe TPI
- Tabla consolidada de todos los índices del proyecto con su tabla,
  clave, condición parcial, origen (TP donde se creó) y mejora
  medida.
- Justificar los ENUMs como restricciones de dominio explícitas
  (alternativa a `CHECK` sobre texto).
- Mencionar `ON DELETE RESTRICT` como decisión deliberada: los pedidos
  con detalles no pueden borrarse físicamente; el borrado lógico es el
  único mecanismo previsto.

### Pendiente documental
Ninguno. El DDL es completo y los índices tienen evidencia de mejora.

---

## Criterio 5 — DML y consultas: JOIN, agregación, subconsultas, GROUP BY/HAVING, funciones de ventana

**Estado: Cubierto**

### Evidencia disponible
- `sql/queries.sql` — cinco epics de casos de uso (HU-CAT, HU-PROD,
  HU-USR, HU-PED) y cinco consultas analíticas (A–E):
  - **A**: `SUM + GROUP BY + ORDER BY + LIMIT` (top 5 productos).
  - **B**: `SUM + GROUP BY` sobre cuatro tablas con `date_trunc`.
  - **C**: `RANK() OVER (ORDER BY SUM(...) DESC)` — función de ventana.
  - **D**: subconsulta escalar `AVG` en `WHERE` (pedidos sobre el promedio).
  - **E**: `LEFT JOIN ... WHERE IS NULL` (anti-join / productos sin ventas).
- `sql/consultas_parte4_tp3.sql` — consultas A y B con alternativas
  equivalentes y verificaciones `EXCEPT` en ambas direcciones (0 filas).
- `sql/consultas_analiticas_tp4.sql` — consultas de ranking con
  `COUNT(DISTINCT)`, `SUM` y `RANK()` sobre cuatro tablas; reescrituras
  con CTEs probadas y descartadas por evidencia real.
- `sql/consultas_parte3_tp4.sql` — Spec A (ranking con `RANK PARTITION BY`)
  y Spec B (subconsulta correlacionada por `id_usuario`); cuatro
  verificaciones `EXCEPT` resultaron en 0 filas.

### Qué debe explicarse o citarse en el informe TPI
- Tabla de consultas con tipo (agregación, ventana, subconsulta,
  anti-join), tablas involucradas y resultado esperado.
- Destacar la subconsulta correlacionada de Spec B (TP4 Parte 3)
  como ejemplo de correlated subquery.
- Mencionar que las alternativas equivalentes se verificaron formalmente
  con `EXCEPT` y no se asumió equivalencia sin prueba.
- Si hay ejemplos de `HAVING`: la consulta D no usa `HAVING`; las
  verificaciones de `carga_masiva_tp3.sql` (V2: detalles por pedido)
  usan `HAVING count(*) <> 2`. Incluir este ejemplo.

### Pendiente documental
Ninguno. La cobertura es amplia.

---

## Criterio 6 — Vistas, funciones y procedimientos almacenados en PL/pgSQL

**Estado: Cubierto**

### Evidencia disponible
**Vistas regulares:**
- `sql/Objects.sql`: cuatro vistas base — `v_productos_vigentes`,
  `v_pedidos_resumen`, `v_pedido_detalle`, `v_categorias_vigentes`.
- `sql/views_tp5.sql`: tres vistas TP5 — `v_tp5_productos_categoria`,
  `v_tp5_pedidos_usuario`, `v_tp5_detalle_pedido_productos` (con
  regla explícita de histórico para productos eliminados).

**Vista materializada:**
- `sql/vista_materializada_tp5.sql`: `mv_tp5_facturacion_categoria_mes`
  con índice único `uq_mv_tp5_facturacion_categoria_mes (id_categoria, mes)`.
  Medición real: consulta directa 706.310 ms vs. lectura de la vista
  0.284 ms. Equivalencia verificada con EXCEPT en ambas direcciones
  (0 filas).

**Funciones:**
- `sql/Objects.sql`:
  - `calcular_total_pedido(BIGINT)` — función SQL STABLE que suma
    subtotales de `detalle_pedido`.
  - `fn_set_subtotal()` — función PL/pgSQL disparada por trigger BEFORE.
  - `fn_recalcular_total()` — función PL/pgSQL disparada por trigger AFTER.
- `sql/restricciones.sql`:
  - `fn_check_estado_transition()` — PL/pgSQL con máquina de estados.
  - `fn_check_categoria_baja_logica()` — PL/pgSQL con verificación de
    productos vigentes asociados.

**Procedimiento almacenado:**
- `sql/Objects.sql`: `sp_crear_pedido(BIGINT, forma_pago, JSONB)` —
  PL/pgSQL con validación de usuario, creación atómica de pedido y
  detalles, bloqueo `SELECT ... FOR UPDATE`, descuento de stock y
  `RAISE EXCEPTION` para violaciones de negocio.

### Qué debe explicarse o citarse en el informe TPI
- Tabla de objetos programáticos con nombre, tipo, archivo, propósito
  y trigger asociado si aplica.
- Describir `sp_crear_pedido` como el único punto de entrada para crear
  pedidos en producción: valida usuario, itera el array JSONB,
  bloquea filas de stock con `FOR UPDATE` y es atómico.
- Mencionar la vista materializada como objeto de lectura con política
  de `REFRESH` diferida; no transaccional.
- Explicar la diferencia entre la función SQL STABLE
  (`calcular_total_pedido`) y las funciones PL/pgSQL de trigger.

### Pendiente documental
Ninguno.

---

## Criterio 7 — Reglas de negocio: CHECK, UNIQUE, triggers

**Estado: Cubierto**

### Evidencia disponible
**CHECK:**
- `precio >= 0`, `stock >= 0`, `total >= 0`, `precio_unitario >= 0`,
  `subtotal >= 0` en `schema.sql`.
- `cantidad > 0` en `detalle_pedido`.

**UNIQUE:**
- `usuario.mail` — no pueden existir dos usuarios con el mismo correo.
- `categoria.nombre_categoria` — nombres de categoría únicos.
- `UNIQUE (id_pedido, id_producto)` en `detalle_pedido` — un producto
  no puede aparecer dos veces en el mismo pedido.

**Triggers de cálculo automático (`sql/Objects.sql`):**
- `trg_subtotal` (`BEFORE INSERT OR UPDATE`, row-level): completa
  `precio_unitario` desde el producto si no se informó, calcula
  `subtotal = cantidad × precio_unitario`.
- `trg_total_ins` y `trg_total_upd` (`AFTER INSERT/UPDATE`, statement-level,
  con Transition Tables `REFERENCING NEW TABLE AS afectados`): recalculan
  `pedido.total` para todos los pedidos afectados en la sentencia.

**Triggers de restricción de integridad (`sql/restricciones.sql`):**
- `trg_check_estado_transition` (`BEFORE UPDATE OF estado`): máquina
  de estados — `PENDIENTE → {CONFIRMADO, CANCELADO}`,
  `CONFIRMADO → {TERMINADO, CANCELADO}`; `TERMINADO` y `CANCELADO`
  son estados finales.
- `trg_check_categoria_baja_logica` (`BEFORE UPDATE OF eliminado`):
  impide dar de baja una categoría que tiene productos vigentes.

**Pruebas:** `sql/test_restricciones.sql` — 10 casos para Regla 1
(4 válidos, 6 inválidos) y 4 casos para Regla 2; todos documentados
con resultado real en `duia_parte1.md`.

### Qué debe explicarse o citarse en el informe TPI
- Tabla de restricciones con tipo (CHECK, UNIQUE, trigger), tabla,
  columna(s) afectadas y mensaje de error en caso de violación.
- Explicar la máquina de estados del pedido con el diagrama de
  transiciones válidas.
- Destacar el uso de `WHEN (OLD.estado IS DISTINCT FROM NEW.estado)`
  para que el trigger de estado no se active en UPDATEs que no cambian
  el campo.
- Mencionar que los triggers de cálculo usan Transition Tables
  (característica de PostgreSQL 10+) para eficiencia: recalculan solo
  los pedidos afectados en la sentencia, no toda la tabla.

### Pendiente documental
Ninguno.

---

## Criterio 8 — Transacciones: atomicidad, COMMIT, ROLLBACK, aislamiento y concurrencia

**Estado: Cubierto**

### Evidencia disponible
- `sql/transacciones.sql` — cuatro escenarios documentados:
  - **Escenario 1**: atomicidad de `sp_crear_pedido` (producto inexistente,
    cantidad 0); los conteos antes/después deben ser iguales.
  - **Escenario 2**: `BEGIN` / `COMMIT` vs. `BEGIN` / `ROLLBACK`
    sobre `UPDATE producto SET stock`; verifica que el ROLLBACK deshace.
  - **Escenario 3**: lectura no repetible con `READ COMMITTED` (nivel
    por defecto) vs. `SERIALIZABLE`; requiere dos terminales.
  - **Escenario 4**: sobreventa sin control (problema demostrado) vs.
    sobreventa con `sp_crear_pedido` y `SELECT ... FOR UPDATE` (solución).
- `sql/carga_masiva_tp3.sql` — transacción explícita `BEGIN` sin COMMIT
  automático; el usuario decide `COMMIT` o `ROLLBACK` después de las
  verificaciones V1–V7.
- `sql/test_restricciones.sql` — cada caso de prueba se envuelve en
  `BEGIN` / `ROLLBACK` para que las excepciones esperadas no dejen
  estado sucio.
- `sql/Objects.sql` — `sp_crear_pedido` es transaccional por diseño:
  `RAISE EXCEPTION` aborta la transacción completa (pedido + detalles).
- `informe_concurrencia.md` — informe separado sobre concurrencia.

### Qué debe explicarse o citarse en el informe TPI
- Diagrama o tabla de los cuatro escenarios de `transacciones.sql`
  con el resultado esperado en cada caso.
- Explicar que `sp_crear_pedido` **no tiene COMMIT explícito**: el
  `COMMIT` o `ROLLBACK` es responsabilidad del llamador; las
  excepciones internas abortan la transacción activa.
- Describir el problema de sobreventa (Escenario 4 versión sin control)
  y cómo `SELECT ... FOR UPDATE` lo resuelve serializando el acceso
  al stock.
- Distinguir `READ COMMITTED` (lectura no repetible posible) vs.
  `SERIALIZABLE` (lecturas estables dentro de la transacción) con el
  ejemplo del Escenario 3.
- Mencionar que `informe_concurrencia.md` profundiza en el análisis
  de los niveles de aislamiento.

### Pendiente documental
Ninguno.

---

## Criterio 9 — Soft delete y su impacto en consultas e índices

**Estado: Cubierto**

### Evidencia disponible
**Columna `eliminado`:** presente en las cinco tablas con
`BOOLEAN NOT NULL DEFAULT FALSE`.

**Filtros en vistas:**
- Cada vista de `Objects.sql` filtra `eliminado = FALSE` de su propia
  tabla sin propagar el filtro a tablas relacionadas
  (`v_pedidos_resumen` filtra `pedido.eliminado` pero no
  `usuario.eliminado`; `v_pedido_detalle` filtra `detalle_pedido.eliminado`
  pero no `producto.eliminado`).
- Las vistas TP5 en `views_tp5.sql` son más estrictas por diseño:
  `v_tp5_pedidos_usuario` filtra ambas tablas (`pedido.eliminado` y
  `usuario.eliminado`); `v_tp5_detalle_pedido_productos`
  intencionalmente **no filtra** `producto.eliminado` para preservar
  el histórico de ventas.

**Impacto en índices:**
- Todos los índices creados en TP3 y TP5 usan `WHERE eliminado = FALSE`
  como condición parcial en lugar de indexar el booleano directamente.
- Se documentó y descartó explícitamente el índice simple
  `ON pedido (eliminado)` por baja cardinalidad
  (en `specs/plan_indexado_tp5.md` e `informe_mediciones_tp5.md`).
- La condición parcial reduce el tamaño del índice, excluye filas
  eliminadas del árbol B-tree y habilita `REFRESH CONCURRENTLY` en la
  vista materializada con un índice único sobre los datos vigentes.

**Dato de seed:** `data.sql` elimina lógicamente productos 4 y 16,
categoría 7 y usuario 8; el pedido #1 de usuario 8 permanece como
registro histórico intacto.

### Qué debe explicarse o citarse en el informe TPI
- Tabla comparativa de vistas de `Objects.sql` vs. vistas TP5,
  indicando qué tablas filtra cada una y la justificación de diseño.
- Explicar la decisión de `v_tp5_detalle_pedido_productos` de no
  filtrar `producto.eliminado` con el argumento de integridad histórica.
- Mostrar un ejemplo concreto con los productos 4 y 16 (eliminados en
  seed): aparecen en `v_tp5_detalle_pedido_productos` pero no en
  `v_tp5_productos_categoria`.
- Argumentar que los índices parciales `WHERE eliminado = FALSE` son
  el patrón correcto para soft delete y explicar por qué un índice
  sobre la columna booleana sola nunca es elegido por el planner.

### Pendiente documental
Ninguno.

---

## Lista priorizada de pendientes reales

Los criterios "Cubiertos" no tienen pendientes de implementación, solo
de documentación en el informe final del TPI. Los pendientes están
ordenados de mayor a menor impacto para la entrega:

| Prioridad | Pendiente | Criterio | Acción mínima |
|---|---|---|---|
| 1 | Dependencias funcionales del esquema final no están listadas en ningún documento del repositorio | 3 | Agregar sección de DF en el informe TPI (una página) |
| 2 | El informe TPI integrador no existe aún como archivo en el repositorio | Todos | Crear `informe_tpi.md` o PDF con la estructura sugerida abajo |
| 3 | La justificación de `precio_unitario` como snapshot (no redundancia) no está escrita explícitamente | 3 | Una oración en la sección de normalización del informe TPI |
| 4 | Tabla consolidada de todos los índices (schema + TP3 + TP5) con mejoras medidas | 4 | Agregar tabla al informe TPI; la información ya está dispersa en los informes de TP |
| 5 | Ejemplos de `HAVING` en el informe (solo aparece en `carga_masiva_tp3.sql` verificaciones) | 5 | Citarlo en la sección de consultas del informe |

---

## Estructura sugerida para el informe técnico del TPI

```
1. Introducción y alcance del proyecto
   - Descripción del dominio (FoodStore, gastronomía)
   - Tecnología: PostgreSQL 17, sin capa de aplicación

2. Modelo ER y diseño conceptual
   - Diagrama ER (referencia a docs/modelo_er_foodstore.jpeg)
   - Entidades, atributos y cardinalidades
   - Evolución del diseño (columnas added post-ER: created_at, imagen)

3. Modelo relacional y normalización
   - Tablas, PK, FK, restricciones
   - Dependencias funcionales por tabla
   - Argumento de 3FN/BCNF (incluir caso especial de precio_unitario)
   - Relaciones 1:N y resolución de la N:M (detalle_pedido)

4. DDL: implementación del esquema
   - Tipos ENUM (rol, estado_pedido, forma_pago)
   - Tablas con CHECK, UNIQUE, NOT NULL
   - Índices base y su justificación

5. Programabilidad: vistas, funciones, triggers y procedimiento
   - Tabla de objetos programáticos
   - Triggers de cálculo (trg_subtotal, trg_total_ins/upd)
   - Triggers de integridad (trg_check_estado_transition, trg_check_categoria_baja_logica)
   - sp_crear_pedido: flujo, validaciones, bloqueo FOR UPDATE
   - Vistas base (Objects.sql) y vistas TP5 (views_tp5.sql)
   - Vista materializada: mv_tp5_facturacion_categoria_mes

6. Consultas y casos de uso
   - Tabla de consultas por tipo (JOIN, agregación, ventana, subconsulta)
   - Consultas analíticas de queries.sql (A–E)
   - Consultas de TP3 Parte 4 y TP4 Parte 3 con verificaciones EXCEPT

7. Optimización: índices y planes de ejecución
   - Tabla consolidada de índices (origen, mejora medida)
   - Metodología: hipótesis → EXPLAIN ANALYZE → aceptar/descartar
   - Ejemplos de índices descartados y por qué
   - Vista materializada como alternativa para agregaciones globales

8. Transacciones, aislamiento y concurrencia
   - Atomicidad de sp_crear_pedido
   - BEGIN/COMMIT vs. BEGIN/ROLLBACK (Escenario 2)
   - READ COMMITTED vs. SERIALIZABLE (Escenario 3)
   - Problema de sobreventa y solución con FOR UPDATE (Escenario 4)

9. Soft delete: diseño y consecuencias
   - Patrón de columna eliminado en todas las tablas
   - Diferencias de filtro entre vistas Objects.sql y vistas TP5
   - Índices parciales WHERE eliminado = FALSE como práctica correcta

10. Conclusiones
    - Qué se implementó, qué se probó con evidencia real
    - Limitaciones y posibles extensiones
```

---

## Checklist de archivos para la entrega

### Ya presentes en el repositorio

- [x] `docs/modelo_er_foodstore.jpeg`
- [x] `docs/informe_tp1_proyecto_foodstore.pdf`
- [x] `sql/schema.sql`
- [x] `sql/Objects.sql`
- [x] `sql/data.sql`
- [x] `sql/queries.sql`
- [x] `sql/transacciones.sql`
- [x] `sql/restricciones.sql`
- [x] `sql/test_restricciones.sql`
- [x] `sql/carga_masiva_tp3.sql`
- [x] `sql/indices_optimizacion_tp3.sql`
- [x] `sql/competencia_optimizacion_tp3.sql`
- [x] `sql/competencia_tp4.sql`
- [x] `sql/consultas_parte4_tp3.sql`
- [x] `sql/consultas_analiticas_tp4.sql`
- [x] `sql/consultas_parte3_tp4.sql`
- [x] `sql/indices_tp5.sql`
- [x] `sql/views_tp5.sql`
- [x] `sql/test_vistas_tp5.sql`
- [x] `sql/vista_materializada_tp5.sql`
- [x] `sql/test_vista_materializada_tp5.sql`
- [x] `informe_tp3.md`
- [x] `informe_tp4.md`
- [x] `informe_mediciones_tp5.md`
- [x] `informe_concurrencia.md`
- [x] `duia_parte1.md`
- [x] `duia_tp3.md`
- [x] `duia_tp4.md`
- [x] `duia_tp5.md`
- [x] `spec_restricciones.md`
- [x] `spec_consultas_tp4.md`
- [x] `specs/plan_indexado_tp5.md`
- [x] `specs/vistas_tp5.md`
- [x] `specs/vista_materializada_tp5.md`
- [x] `README.md`

### Faltantes o a crear para la entrega final

- [ ] `informe_tpi.md` (o PDF equivalente) — documento integrador con
  la estructura de las 10 secciones sugeridas arriba.
- [ ] Sección de dependencias funcionales — puede ir dentro del informe
  TPI o como `specs/normalizacion_tpi.md` si se prefiere separado.
- [ ] Tabla consolidada de índices — puede ir dentro del informe TPI
  o como anexo referenciando los archivos de informe de cada TP.

### Backups (no versionados, pero recomendados como adjunto)

- [ ] Backup de `foodstore_tp2` (pre-restricciones): ya en `backups/`.
- [ ] Backup de `foodstore_tp5` (estado final con todos los objetos TP5):
  no está aún en `backups/`; recomendado antes de la entrega.
