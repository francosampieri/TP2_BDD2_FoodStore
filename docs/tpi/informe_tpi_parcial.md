# Informe TPI — Primera Entrega Parcial — FoodStore

Sistema de gestión de pedidos gastronómicos modelado íntegramente en base de datos. Este informe integra los resultados de los trabajos prácticos y cubre los nueve criterios de la consigna. Como no existe capa de aplicación, toda la lógica vive en SQL (`sql/`), en PostgreSQL 17.

---

## 1. Alcance y tecnología

- **Dominio:** pedidos gastronómicos (catálogo por categorías, usuarios, pedidos y detalle de líneas). Sin capa de aplicación: el esquema, los objetos programables y las consultas son la totalidad del sistema.
- **Motor y lenguaje:** PostgreSQL 17 con PL/pgSQL para funciones, triggers y el procedimiento transaccional `sp_crear_pedido`.
- **Estructura del proyecto:** `sql/schema.sql` (esquema), `sql/Objects.sql` (vistas, funciones, triggers, procedimiento), `sql/data.sql` (seed), `sql/queries.sql` (casos de uso), más los scripts por TP (`restricciones.sql`, `carga_masiva_tp3.sql`, `indices_*.sql`, `views_tp5.sql`, `vista_materializada_tp5.sql`).
- **Bases de trabajo sucesivas:** `foodstore` (esquema y datos), `foodstore_tp2` (restricciones), `foodstore_tp3` (carga masiva, optimización y reescrituras TP4) y `foodstore_tp5` (índices, vistas y vista materializada). El orden de ejecución y las bases se documentan en `README.md`.

## 2. Modelo ER y paso al modelo relacional

- **Diagrama ER:** `docs/modelo/modelo_er_foodstore.jpeg` (diseño conceptual inicial, descrito en `docs/modelo/informe_tp1_proyecto_foodstore.pdf`).
- **Entidades:** `categoria`, `producto`, `usuario`, `pedido` y `detalle_pedido`.
- **Relaciones 1:N** (implementadas en `sql/schema.sql`):
  - `categoria (1) → producto (N)`: FK `producto.id_categoria REFERENCES categoria(id_categoria)`.
  - `usuario (1) → pedido (N)`: FK `pedido.id_usuario REFERENCES usuario(id_usuario)`.
  - `pedido (1) → detalle_pedido (N)`: FK `detalle_pedido.id_pedido REFERENCES pedido(id_pedido) ON DELETE RESTRICT`.
- **Relación N:M resuelta:** la relación muchos-a-muchos `pedido ↔ producto` se resuelve con la tabla de intersección `detalle_pedido`, que incorpora atributos propios de la relación: `cantidad`, `precio_unitario` (snapshot del precio al momento de la venta) y `subtotal`, y se refuerza con `UNIQUE (id_pedido, id_producto)` (un producto no puede repetirse en el mismo pedido). El informe TP1 justifica por qué no puede plantearse como binaria 1:N (se perdería la historia de reventa o el carrito múltiple).
- `ON DELETE RESTRICT` impide el borrado físico de pedidos con detalles: el borrado lógico es el mecanismo previsto.

## 3. Normalización

Fuente: `specs/tpi/evidencia_normalizacion_tpi.md` y secciones "Normalización" de `docs/modelo/informe_tp1_proyecto_foodstore.pdf`.

### Dependencias funcionales del esquema final (`sql/schema.sql`)

- `categoria`: `id_categoria → nombre_categoria, descripcion_categoria, eliminado, created_at`.
- `producto`: `id_producto → nombre_producto, precio, descripcion_producto, stock, imagen, disponible, id_categoria, eliminado, created_at`.
- `usuario`: `id_usuario → nombre_usuario, apellido, mail, celular, contrasena, rol, eliminado, created_at`; además `mail → id_usuario` (clave candidata natural por `UNIQUE`).
- `pedido`: `id_pedido → fecha, estado, total, forma_pago, id_usuario, eliminado, created_at`.
- `detalle_pedido`: `id_detalle → cantidad, precio_unitario, subtotal, id_pedido, id_producto, eliminado, created_at` y `(id_pedido, id_producto) → id_detalle` (clave natural alternativa por `UNIQUE`).

### Formas normales

- **1FN:** atributos atómicos; los ítems del pedido son filas de `detalle_pedido`, no un campo compuesto en `pedido`. El JSONB de `sp_crear_pedido` es un parámetro de entrada, no una columna almacenada.
- **2FN:** PK simples en `categoria`, `producto`, `usuario` y `pedido`; en `detalle_pedido` no hay dependencias parciales (los atributos dependen de la línea completa, con dos claves candidatas: `id_detalle` y `(id_pedido, id_producto)`).
- **3FN/BCNF:** no hay dependencias transitivas: `nombre_categoria` no se almacena en `producto` (se resuelve por JOIN); los datos del usuario no se replican en `pedido`; `mail` cumple BCNF por ser superclave. Casos especiales justificados abajo.

### `precio_unitario` como snapshot histórico (incorporado en la implementación)

`precio_unitario` no estaba en el ER inicial de `DETALLE_PEDIDO`; se incorporó en la implementación. Almacena el precio **al momento de la venta** y lo captura automáticamente el trigger `trg_subtotal` (`BEFORE INSERT OR UPDATE` en `detalle_pedido`, en `sql/Objects.sql`). No es una dependencia transitiva porque una vez que `producto.precio` cambia, `precio_unitario` ya no puede derivarse de ninguna otra columna: es un hecho inmutable del registro contable.

### `subtotal` y `total` como desnormalización controlada por triggers

- `subtotal = cantidad × precio_unitario` lo mantiene `trg_subtotal` (nunca se asigna manualmente).
- `total` lo recalculan `trg_total_ins`/`trg_total_upd` (`AFTER`, statement-level, con Transition Tables `REFERENCING NEW TABLE AS afectados`) vía `calcular_total_pedido()`.
- Son desnormalizaciones intencionales, documentadas y controladas por el motor, equivalentes a columnas calculadas persistentes: evitan re-agregar cientos de miles de filas en cada listado/facturación.

### Diferencias reales entre el ER inicial y `schema.sql`

| Aspecto | ER inicial | `schema.sql` |
|---|---|---|
| `precio_unitario` en `detalle_pedido` | No estaba | Incorporado en la implementación (snapshot histórico; `trg_subtotal` lo captura) |
| `id_detalle` (PK de `detalle_pedido`) | Ya era PK | Se mantiene: `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` |
| `eliminado` (soft delete) | Ya aparecía en las cinco entidades | Concretado: `BOOLEAN NOT NULL DEFAULT FALSE` en las 5 tablas |
| `created_at` | Ya aparecía en las cinco entidades | Concretado: `TIMESTAMPTZ NOT NULL DEFAULT now()` en las 5 tablas |
| `imagen` en `producto` | Ya aparecía en PRODUCTO | Concretado: `VARCHAR(255)` |
| Clave de `usuario` en `pedido` | `usuario_id` (denominación del ER) | `id_usuario` (prefijo `id_`, consistente con las demás PK) |
| Descripciones | `descripcion` (genérica) | `descripcion_categoria`, `descripcion_producto` (nombre técnico prefijado por tabla) |
| Tipos | Texto genérico | PostgreSQL más precisos: `ENUM` (`rol`, `estado_pedido`, `forma_pago`), `NUMERIC(10,2)`/`NUMERIC(12,2)`, `BIGINT GENERATED ALWAYS AS IDENTITY`, `DATE`, `TIMESTAMPTZ`, `VARCHAR(n)`, defaults |
| Restricciones | No representadas en el ER | `CHECK`, `UNIQUE`, `ON DELETE RESTRICT` |

La **única incorporación funcional** de la implementación es `precio_unitario`, que protege la facturación histórica (snapshot que ya no puede derivarse de `producto.precio` una vez que este cambia). Los demás elementos (`id_detalle`, `eliminado`, `created_at` e `imagen`) ya estaban modelados en el ER inicial: `schema.sql` los concretó con tipos, defaults y restricciones PostgreSQL y normalizó la denominación de claves y descripciones. Son concreciones de tipos/denominaciones, no atributos agregados.

## 4. DDL e integridad (`sql/schema.sql`)

- **PK:** `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` en las cinco tablas.
- **ENUM (restricción de dominio):** `rol ('ADMIN','USUARIO')`, `estado_pedido ('PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO')`, `forma_pago ('TARJETA','TRANSFERENCIA','EFECTIVO')`.
- **FK:** `REFERENCES` con `ON DELETE RESTRICT` donde corresponde (`detalle_pedido.id_pedido`).
- **CHECK:** `precio >= 0`, `stock >= 0`, `total >= 0`, `precio_unitario >= 0`, `subtotal >= 0`, `cantidad > 0`.
- **UNIQUE:** `usuario.mail`, `categoria.nombre_categoria`, `(id_pedido, id_producto)` en `detalle_pedido`.
- **Índices base:** `idx_producto_id_categoria`, `idx_id_pedido_usuario`, `idx_producto_nombre` (parcial `WHERE eliminado = FALSE`), `idx_pedido_fecha`.
- **Soft delete:** `eliminado BOOLEAN NOT NULL DEFAULT FALSE` en las cinco tablas; todas las vistas filtran `eliminado = FALSE` en su propio alcance (ver sección 9).

## 5. DML y consultas

Fuente: `sql/queries.sql` (cinco epics HU-* y consultas analíticas A–E).

- **JOIN y agregación:** A) top 5 productos por cantidad (`SUM(cantidad)` + `GROUP BY` + `ORDER BY` + `LIMIT`); B) facturación mensual por categoría sobre cuatro tablas (`SUM(subtotal)` + `date_trunc('month', fecha)`).
- **Funciones de ventana:** C) ranking de usuarios (`RANK() OVER (ORDER BY SUM(total) DESC)`, `pedido`+`usuario`). En TP4 Parte 3 (`sql/consultas_parte3_tp4.sql`) Spec A usa `RANK() OVER (PARTITION BY id_categoria ...)`.
- **Subconsultas:** D) pedidos sobre el promedio general (subconsulta escalar `AVG` en `WHERE`, sin `HAVING`); Spec B de TP4 Parte 3 es una subconsulta correlacionada por `id_usuario`.
- **Anti-join:** E) productos sin ventas (`LEFT JOIN ... WHERE id_detalle IS NULL`).
- **GROUP BY / HAVING:** en `sql/carga_masiva_tp3.sql`, verificación V2 usa `GROUP BY id_pedido HAVING count(*) <> 2` (detecta pedidos que no tienen exactamente dos detalles) y V5 `HAVING count(*) > 1` (mails duplicados).
- **Equivalencias verificadas formalmente con `EXCEPT`** (todas las columnas, ambas direcciones, 0 filas): TP3 Parte 4 (`sql/consultas_parte4_tp3.sql`, 4 verificaciones) y TP4 Parte 3 (`sql/consultas_parte3_tp4.sql`, 4 verificaciones: A.1, A.2, B.1, B.2).

## 6. Objetos programables

- **Vistas regulares** — `sql/Objects.sql`: `v_productos_vigentes`, `v_pedidos_resumen`, `v_pedido_detalle`, `v_categorias_vigentes`. — `sql/views_tp5.sql`: `v_tp5_productos_categoria`, `v_tp5_pedidos_usuario`, `v_tp5_detalle_pedido_productos`.
- **Vista materializada** — `sql/vista_materializada_tp5.sql`: `mv_tp5_facturacion_categoria_mes` con índice único `uq_mv_tp5_facturacion_categoria_mes (id_categoria, mes)`; objeto de lectura con `REFRESH` diferido, no transaccional (ver sección 9).
- **Funciones** — `sql/Objects.sql`: `calcular_total_pedido` (SQL `STABLE`, suma subtotales), `fn_set_subtotal` y `fn_recalcular_total` (PL/pgSQL disparadas por trigger). — `sql/restricciones.sql`: `fn_check_estado_transition` (máquina de estados) y `fn_check_categoria_baja_logica` (baja de categorías con productos vigentes).
- **Procedimiento** — `sql/Objects.sql`: `sp_crear_pedido(p_id_usuario, p_forma_pago, p_items JSONB)` es el único punto de entrada para crear pedidos: valida el usuario, itera el array JSONB, bloquea cada fila de stock con `SELECT ... FOR UPDATE` y descuenta stock; es atómico por diseño (un `RAISE EXCEPTION` aborta la transacción completa).

## 7. Reglas de negocio

- **Transiciones de estado del pedido** (`sql/restricciones.sql`, `trg_check_estado_transition`): `PENDIENTE → {CONFIRMADO, CANCELADO}`, `CONFIRMADO → {TERMINADO, CANCELADO}`; `TERMINADO` y `CANCELADO` son estados finales. Usa `WHEN (OLD.estado IS DISTINCT FROM NEW.estado)` para no dispararse en updates que no cambian el campo.
- **Baja lógica de categorías** (`trg_check_categoria_baja_logica`): impide `categoria.eliminado = TRUE` si la categoría tiene productos vigentes; la reactivación siempre está permitida.
- **Cálculos automáticos** (`sql/Objects.sql`): `trg_subtotal` completa `precio_unitario` y calcula `subtotal`; `trg_total_ins`/`trg_total_upd` recalculan `pedido.total` solo de los pedidos afectados (Transition Tables, PostgreSQL 10+). No se informan manualmente en los `INSERT` (`data.sql`, `carga_masiva_tp3.sql`).
- **Pruebas:** `sql/test_restricciones.sql` con 10 casos para la Regla 1 (4 válidos, 6 inválidos) y 4 casos para la Regla 2, cada uno dentro de `BEGIN`/`ROLLBACK`; resultados reales en `docs/tp2/duia_parte1.md`.

## 8. Transacciones y concurrencia

Fuente: `sql/transacciones.sql` (y `docs/tp2/informe_concurrencia.md` para el análisis de aislamiento).

- **Escenario 1 — Atomicidad:** `sp_crear_pedido` con producto inexistente o cantidad 0 lanza excepción y **no deja** pedidos ni detalles (conteos antes/después iguales). El procedimiento no contiene `COMMIT` interno: el llamador decide el desenlace de la transacción envolvente.
- **Escenario 2 — COMMIT vs ROLLBACK:** `UPDATE producto SET stock` dentro de `BEGIN`; con `COMMIT` persiste, con `ROLLBACK` se deshace.
- **Escenario 3 — Aislamiento:** lectura no repetible demostrada con `READ COMMITTED` (nivel por defecto, la sesión A vuelve a leer el valor cambiado por B) vs. `SERIALIZABLE` (A mantiene la lectura estable). Requiere dos sesiones.
- **Escenario 4 — Sobreventa:** sin control, dos terminales venden más unidades que el stock; con `sp_crear_pedido` y `SELECT ... FOR UPDATE` sobre `producto`, la segunda sesión espera el lock y termina con error de stock insuficiente en lugar de sobrevender.
- Además: `carga_masiva_tp3.sql` abre `BEGIN` explícito sin `COMMIT` automático (el usuario decide tras las verificaciones V1–V7), y `test_restricciones.sql` aísla cada caso esperado a fallar en `BEGIN`/`ROLLBACK`.

## 9. Optimización, índices y vistas

### Carga masiva (TP3 Parte 1, `docs/tp3/informe_tp3.md`)

`sql/carga_masiva_tp3.sql` cargó set-based sobre `foodstore_tp3`: 50.000 productos, 20.000 usuarios, 200.000 pedidos y 400.000 detalles (exactamente 2 por pedido), dentro de una transacción única con verificaciones V1–V7 (todas 0 filas en los checks que esperaban 0 filas), seguida de `ANALYZE` tras el `COMMIT`.

### Mediciones reales (antes → después, `EXPLAIN ANALYZE`)

| Consulta | Antes | Después | Mejora | Índice (origen) |
|---|---|---|---|---|
| Q3 TP3: detalle por producto | 406.794 ms | 16.355 ms | ~25x | `idx_detalle_pedido_producto_vig` (TP3) |
| Consulta común TP3/TP4: productos por categoría y precio | 93.394 ms | 10.855 ms | ~8.6x | `idx_producto_cat_precio_disp_vig` (TP3/TP4) |
| TP5: pedidos cancelados | 210.677 ms | 2.822 ms | ~74.7x | `idx_pedido_cancelado_fecha_vig` (TP5) |
| TP5: productos no disponibles | 31.581 ms | 2.767 ms | ~11.4x | `idx_producto_no_disponible_nombre_vig` (TP5) |
| TP5: detalles con cantidad >= 5 | 182.874 ms | 1.498 ms | ~122x | `idx_detalle_cantidad_excepcional_vig` (TP5) |
| Vista materializada: facturación mensual | 706.310 ms | 0.284 ms | ~2487x | `mv_tp5_facturacion_categoria_mes` (TP5) |

Fuentes: `docs/tp3/informe_tp3.md`, `docs/tp4/informe_tp4.md`, `docs/tp5/informe_mediciones_tp5.md`. Para la vista materializada se usó la **comparación más justa** (la misma consulta directa dentro del mismo bloque de pruebas: 706.310 vs. 0.284 ms); la variación entre mediciones de la directa (1192.272 vs. 706.310 ms) responde a caché/ejecución y no se atribuye a cambios de diseño.

### Índices descartados por evidencia real o falta de selectividad

- **TP3 Q1** (`idx_producto_cat_precio_vig`): 7.744 → 57.370 ms, descartado. **TP3 Q2** (`idx_pedido_fecha_conf_vig`): 182.260 → 288.887 ms, descartado. Solo se conservó el índice de Q3.
- **TP4 Parte 1** (reeescrituras, no índices): facturación agrupando por `id_categoria` 1089,669 ms vs. 946,611 ms (el `Partial HashAggregate` empeoró); ranking con pre-agregación por pedido 2599,644 ms vs. 1283,410 ms (`HashAggregate` volcando a disco). Ambas descartadas.
- **Índice simple sobre `pedido (eliminado)`**: baja cardinalidad, nunca elegido por el planner.
- **Índices para agregaciones globales sin filtro selectivo**: no evitan recorrer las tablas completas.
- **Índice general sobre `pedido (total)`** para "total mayor al promedio": devolvía 88.369 de 200.021 pedidos, no selectivo.

### Soft delete e impacto en consultas e índices

- Patrón `eliminado BOOLEAN NOT NULL DEFAULT FALSE` en las 5 tablas (`schema.sql`).
- Vistas de `Objects.sql` filtran solo su propia tabla; las vistas TP5 son más estrictas por diseño: `v_tp5_pedidos_usuario` filtra `pedido` y `usuario` (y no expone `contrasena`, `celular` ni `rol`); `v_tp5_detalle_pedido_productos` **no** filtra `producto.eliminado` para conservar el histórico de ventas (validado por diseño y equivalencia; la base no tiene casos vigentes de productos eliminados con detalles).
- Índices parciales `WHERE eliminado = FALSE` (`idx_producto_nombre`, índices TP3/TP5) son el patrón correcto para soft delete: reducen el árbol y excluyen filas eliminadas.
- La vista materializada filtra `dp.eliminado = FALSE` y `ped.eliminado = FALSE` (clasificación histórica de producto/categoría sin filtrar) y se actualiza con `REFRESH MATERIALIZED VIEW CONCURRENTLY` (requiere el índice único; nunca por cada `INSERT`; puede quedar desactualizada entre refreshes y **no** sirve para stock, pedidos activos ni operaciones transaccionales).

## 10. Pruebas y resultados

Todo lo anterior fue probado manualmente en DBeaver con evidencia real:

| Área | Pruebas | Resultado documentado |
|---|---|---|
| Restricciones | `test_restricciones.sql`, 14 casos | Real en `docs/tp2/duia_parte1.md` (excepciones esperadas confirmadas) |
| Carga masiva | V1–V7 | 0 filas en los checks, conteos correctos (`docs/tp3/informe_tp3.md`) |
| Equivalencias | `EXCEPT` ×4 (TP3 P4) y ×4 (TP4 P3) | 0 filas en cada dirección (`docs/tp3/informe_tp3.md`, `docs/tp4/informe_tp4.md`) |
| Vistas TP5 | `test_vistas_tp5.sql` (V1.1–V3.2) | Seis EXCEPT 0 filas; control V3.3 informativo (`test_vistas_tp5.sql`) |
| Vista materializada | `test_vista_materializada_tp5.sql` | Excepciones A/B 0 filas; lectura 0.284 ms (`docs/tp5/informe_mediciones_tp5.md`) |
| Concurrencia | `transacciones.sql` escenarios 1–4 (3 y 4 con dos sesiones) | `docs/tp2/informe_concurrencia.md`, `docs/tp4/informe_tp4.md` |

## 11. Uso de IA

- **Kiro — especificaciones:** redactó las specs que guiaron la implementación y la auditoría del TPI: `specs/tp2/spec_restricciones.md`, `specs/tp4/spec_consultas_tp4.md`, `specs/tp5/plan_indexado_tp5.md`, `specs/tp5/vistas_tp5.md`, `specs/tp5/vista_materializada_tp5.md`, `specs/tpi/auditoria_tpi_parcial.md` y `specs/tpi/evidencia_normalizacion_tpi.md`.
- **OpenCode — propuestas y archivos:** generó los scripts SQL de cada TP (`restricciones.sql`, `carga_masiva_tp3.sql`, `indices_*.sql`, `consultas_parte*.sql`, `views_tp5.sql`, `vista_materializada_tp5.sql`, `test_*.sql`) y los informes integradores (`docs/tp3/informe_tp3.md`, `docs/tp4/informe_tp4.md`, `docs/tp5/informe_mediciones_tp5.md`, este informe y DUIAs).
- **Codex — guía, revisión y coordinación:** revisó trazabilidad de archivos y cifras, coordinó la corrección de la evolución ER → `schema.sql` (ver `docs/tpi/duia_tpi_parcial.md`) y veló por la coherencia entre secciones.
- **Aclaración de método:** ninguna decisión se aceptó por propuesta de IA sin prueba. Las aceptaciones y los descartes se validaron con **pruebas manuales en DBeaver** (mensajes de excepción reales, `EXPLAIN ANALYZE` con Execution Time, verificaciones `EXCEPT` en 0 filas). El detalle punto a punto de qué se aceptó y qué se corrigió/descartó, y por qué, está en las DUIA específicas: `docs/tp2/duia_parte1.md`, `docs/tp3/duia_tp3.md`, `docs/tp4/duia_tp4.md`, `docs/tp5/duia_tp5.md` y `docs/tpi/duia_tpi_parcial.md`.

## 12. Conclusión

Se implementó y verificó con evidencia real un esquema 3FN/BCNF con soft delete, objetos programables (vistas, funciones, triggers, procedimiento transaccional `sp_crear_pedido`), reglas de negocio por restricciones, pruebas de concurrencia con dos sesiones y una estrategia de optimización basada en hipótesis → `EXPLAIN ANALYZE` → aceptar/descartar (mejoras medidas de ~8.6x a ~2487x). Las limitaciones: los tiempos dependen de la carga de la base de trabajo y no son exactamente reproducibles en otra máquina. Extensiones posibles: particionado por fecha en `pedido`/`detalle_pedido` y una política programada de `REFRESH` para la vista materializada.

**Repositorio:** https://github.com/francosampieri/TP2_BDD2_FoodStore.git
