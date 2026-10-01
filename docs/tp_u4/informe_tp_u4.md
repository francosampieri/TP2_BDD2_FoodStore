# Informe — TP Unidad 4: FNBC y Desnormalización Controlada — Food Store

> Resultados verificados en DBeaver sobre `foodstore_tp_u4` (PostgreSQL 17).
> Los tiempos de ejecución corresponden a esta instancia y a esta medición.

---

## 1. Introducción

- **Base de trabajo:** `foodstore_tp_u4`, copia de `foodstore_tp5` (PostgreSQL 17).
- **Parte 1 (FNBC):** descomposición de `ControlLoteAlmacen` hasta FNBC con
  instancia de ejemplo, migración y verificación de unión sin pérdida
  (`sql/tp_fnbc_control_lote.sql`).
- **Parte 2 (Desnormalización controlada):** top 5 diario de categorías por
  monto vendido con vista materializada y auditoría de equivalencia
  (`sql/tp_desnormalizacion_top_categorias.sql`).
- Toda afirmación se acompaña del artefacto SQL o de la salida real de
  `EXPLAIN ANALYZE`/`EXCEPT` que la demuestra.

---

## 2. Parte 1 — Análisis y aplicación de la FNBC

### 2.1 Relación original y dependencias funcionales

Relación original (consigna):

```
ControlLoteAlmacen(LoteID, DepositoID, ResponsableControlID)
PK: (LoteID, DepositoID)
```

Dependencias funcionales que se desprenden de la regla de negocio:

```
DF1:  (LoteID, DepositoID) → ResponsableControlID
DF2:  ResponsableControlID → DepositoID
```

Justificación semántica:

- **DF1:** para un lote y un depósito interviniente dados, el responsable de
  control queda unívocamente determinado.
- **DF2:** cada responsable de control pertenece a un único depósito (dato
  maestro de personal); conocer el responsable es suficiente para saber el
  depósito. **DF2 es la que viola FNBC.**

### 2.2 Clausuras y claves candidatas

```
{LoteID, DepositoID}+        = {LoteID, DepositoID, ResponsableControlID}   (DF1)
{LoteID, ResponsableControlID}+ = {LoteID, ResponsableControlID, DepositoID} (DF2)
{LoteID}+                    = {LoteID}
{ResponsableControlID}+      = {ResponsableControlID, DepositoID}           (DF2)
```

**Claves candidatas:**
- `{LoteID, DepositoID}` — la PK declarada en la consigna.
- `{LoteID, ResponsableControlID}` — derivada de DF2.

**Atributos primos y no primos:** los **tres atributos son primos** (cada uno
pertenece a alguna clave candidata). No hay atributos no primos.

| Atributo | Clasificación | Razón |
|---|---|---|
| `LoteID` | Primo | Pertenece a ambas claves candidatas |
| `DepositoID` | Primo | Pertenece a `{LoteID, DepositoID}` |
| `ResponsableControlID` | Primo | Pertenece a `{LoteID, ResponsableControlID}` |

### 2.3 Diagnóstico de violación de FNBC

Definición formal de FNBC: una relación está en FNBC si y solo si para toda
dependencia funcional no trivial `X → Y`, `X` es superclave.

- **DF1** `(LoteID, DepositoID) → ResponsableControlID`: el determinante es
  clave candidata (superclave) → **no viola** FNBC.
- **DF2** `ResponsableControlID → DepositoID`: `{ResponsableControlID}` **no es
  superclave** (su clausura no incluye `LoteID`) y la dependencia es no trivial
  → **viola FNBC**.

Conclusión: `control_lote_almacen` **no está en FNBC por DF2**. Sí cumple 3FN:
en cada dependencia no trivial, el determinante es superclave o el atributo
determinado es primo. Aquí `DepositoID` es primo, aunque
`ResponsableControlID` no sea superclave.

Redundancia concreta en la instancia: `ResponsableControlID = 801` aparece en
los lotes 501 y 502, por lo que `DepositoID = 30` se almacena dos veces.

### 2.4 Las tres anomalías clásicas sobre la instancia de la consigna

- **Anomalía de inserción:** no puede registrarse que un nuevo responsable de
  control pertenece a un depósito (p. ej., "el responsable 803 trabaja en el
  depósito 31") mientras ese responsable no tenga todavía un par
  (lote, depósito). Como la PK es `(lote_id, deposito_id)`, se vería obligado a
  inventar un lote ficticio o información en blanco; el dato maestro del
  personal queda bloqueado hasta que exista una asignación operativa.
- **Anomalía de borrado:** si el control del lote 503 concluye y se elimina la
  tupla `(503, 31, 802)`, se pierde junto con ella el hecho independiente de que
  el responsable 802 está asignado al depósito 31. Un borrado operativo destruye
  un dato maestro que no dependía del lote.
- **Anomalía de actualización:** si el responsable 801 pasa del depósito 30 al
  depósito 40, hay que modificarlo en las **dos** tuplas donde aparece
  `(501, 30, 801)` y `(502, 30, 801)`. Si por error se actualiza solo una fila,
  la base queda inconsistente: el mismo responsable aparecería en dos depósitos
  distintos, contradiciendo DF2.

### 2.5 Descomposición sin pérdida

Se extrae DF2 en una relación aparte:

```
R1(ResponsableControlID, DepositoID)
    PK: ResponsableControlID          ← contiene DF2 (responsable → depósito)

R2(LoteID, ResponsableControlID)
    PK: (LoteID, ResponsableControlID) ← DF1 se verifica vía reunión con R1
```

**Justificación de la unión sin pérdida (criterio de superclave / teorema de
Heath):**

```
R1 ∩ R2 = {ResponsableControlID}
```

`ResponsableControlID` es la PK de R1 → el atributo común es superclave de R1 →
`R1 ⋈ R2 = ControlLoteAlmacen` sin filas espurias. Sobre la instancia:

| LoteID | DepositoID | ResponsableControlID |
|---|---|---|
| 501 | 30 | 801 |
| 502 | 30 | 801 |
| 503 | 31 | 802 |

→ de la instancia se proyectan R1 `{801→30, 802→31}` y R2
`{501→801, 502→801, 503→802}`; la reunión de esas proyecciones reconstruye
las tres filas. La reconstrucción se verificó en DBeaver con la vista de
compatibilidad y la auditoría EXCEPT (2.8).

> **Preservación de DF1 (aclaración obligatoria):** la descomposición **no
> preserva automáticamente** la DF `(lote_id, deposito_id) →
> responsable_control_id`; esa DF no queda contenida en ninguna relación
> individual y **puede requerir control adicional** (trigger o lógica de
> aplicación). Lo que sí se demuestra es la **reunión sin pérdida**, verificada
> sobre los datos por la vista de compatibilidad y la auditoría EXCEPT (2.8).

### 2.6 Tablas SQL creadas (`sql/tp_fnbc_control_lote.sql`)

Ejecutadas en `foodstore_tp_u4` por bloques. **Corrección respecto del plan:**
las tablas maestras usan `BIGINT PRIMARY KEY` **sin IDENTITY** para conservar
los IDs literales de la consigna; R1/R2 usan esos IDs literales y el vínculo con
`usuario` se hace por una tabla de correspondencia separada.

| Relación | Tabla SQL | PK | FKs |
|---|---|---|---|
| (maestra) | `tp_u4_deposito(id_deposito, nombre)` | `id_deposito` | — |
| (maestra) | `tp_u4_lote(id_lote, nombre)` | `id_lote` | — |
| (maestra) | `tp_u4_responsable_control(id_responsable, nombre)` | `id_responsable` | — |
| original | `control_lote_almacen(lote_id, deposito_id, responsable_control_id)` | `(lote_id, deposito_id)` | → tres maestras |
| R1 | `tp_u4_r1_responsable_deposito(responsable_control_id, deposito_id)` | `responsable_control_id` | → responsable, depósito |
| R2 | `tp_u4_r2_lote_responsable(lote_id, responsable_control_id)` | `(lote_id, responsable_control_id)` | → lote, R1 |
| correspondencia | `tp_u4_responsable_usuario(id_responsable, id_usuario)` | `id_responsable` | → responsable, `usuario` |

IDs literales insertados: depósitos `30, 31`; lotes `501, 502, 503`;
responsables `801, 802`. La tabla de correspondencia mapea `801 → usuario 1` y
`802 → usuario 2` (Admin Garcia y Ana Gomez del seed) con FK a `usuario`
El script comprueba la vigencia de los usuarios 1 y 2 antes de crear esta
correspondencia.

### 2.7 Vista de compatibilidad

`tp_u4_v_control_lote_almacen` devuelve exactamente `lote_id`, `deposito_id`,
`responsable_control_id` con los IDs literales, vía `R2 JOIN R1 ON
responsable_control_id`.

Verificación visual (BLOQUE 11): **6 filas**, tres originales y tres
reconstruidas, alineadas por lote y con los mismos valores.

### 2.8 Verificación de equivalencia (EXCEPT bidireccional)

| Dirección | Consulta | Resultado |
|---|---|---|
| A | `control_lote_almacen` EXCEPT `vista` | **0 filas** |
| B | `vista` EXCEPT `control_lote_almacen` | **0 filas** |

La comparación se hace **contra la tabla original** (no contra una repetición
manual del mismo JOIN).

---

## 3. Parte 2 — Desnormalización controlada

### 3.1 Comprobación previa de ventas del día

Query de comprobación (cuenta **detalles** vigentes de pedidos vigentes de hoy;
contar solo pedidos no demuestra que haya ventas):

```sql
SELECT COUNT(*) AS detalles_vigentes_del_dia
FROM   detalle_pedido dp
JOIN   pedido         ped ON ped.id_pedido = dp.id_pedido
                          AND ped.eliminado = FALSE
                          AND ped.fecha = CURRENT_DATE
WHERE  dp.eliminado = FALSE;
```

La comprobación inicial devolvió **0 detalles**. Para disponer de un caso del
día se creó un pedido de prueba mediante `sp_crear_pedido` en esta copia de la
base, después de comprobar usuario, disponibilidad y stock. La comprobación
posterior devolvió **2 detalles vigentes del día**. El procedimiento usa la
fecha actual por defecto y descuenta stock dentro de la transacción.

### 3.2 Consulta base (reporte) y MEDICIÓN 1 — antes

Consulta adaptada a las columnas reales de `schema.sql` (4 tablas: `detalle_pedido`
→ `producto` → `categoria`, y `pedido` para filtrar fecha y no eliminados):

```sql
SELECT c.id_categoria, c.nombre_categoria, SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido ped ON ped.id_pedido = dp.id_pedido
                 AND ped.eliminado = FALSE
                 AND ped.fecha = CURRENT_DATE
JOIN   producto pr ON pr.id_producto = dp.id_producto
JOIN   categoria c ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria
ORDER  BY monto_vendido DESC
LIMIT  5;
```

`EXPLAIN (ANALYZE, BUFFERS)` — BLOQUE 2:

| # | Consulta | Execution Time | Nodo dominante |
|---|---|---|---|
| 1 | Directa (antes de la vista) | **4,335 ms** | `Nested Loop` entre pedido, detalle, producto y categoría; después `GroupAggregate` y `Sort` |

### 3.3 Patrón elegido y justificación

**Patrón: vista materializada** (`mv_tp_u4_top5_cat_dia`).

- **Evidencia que motiva la decisión:** la MEDICIÓN 1 tardó 4,335 ms y
  resolvió las reuniones, la agregación y el ordenamiento en cada lectura.
  El índice `idx_pedido_fecha` localizó el pedido del día y el índice de
  `detalle_pedido` encontró sus dos líneas: esta ejecución **no recorrió**
  los más de 400.000 detalles históricos. Si el panel repite la consulta,
  vuelve a pagar el trabajo de reunión y agregación. El tiempo medido es
  pequeño y por sí solo no demuestra un cuello de botella en esta jornada.
- **Mecanismo de actualización:** `REFRESH MATERIALIZED VIEW` (con
  `CONCURRENTLY` una vez creado el índice único) re-ejecuta la agregación contra
  las tablas base; la vista no se alimenta por escrituras manuales.
- **Reversibilidad sin pérdida:** la vista es derivable 100% de las tablas base;
  `DROP MATERIALIZED VIEW` no pierde información. La auditoría EXCEPT (3.7)
  confirmó equivalencia con las tablas base inmediatamente después de poblarla.

### 3.4 Vista materializada e índice único

Definición **sin LIMIT ni ORDER BY** (el top 5 se aplica al consultar), una fila
por categoría con ventas en el día:

```sql
CREATE MATERIALIZED VIEW mv_tp_u4_top5_cat_dia AS
SELECT c.id_categoria, c.nombre_categoria, SUM(dp.subtotal) AS monto_vendido
FROM   detalle_pedido dp
JOIN   pedido ped ON ped.id_pedido = dp.id_pedido AND ped.eliminado = FALSE
                 AND ped.fecha = CURRENT_DATE
JOIN   producto pr ON pr.id_producto = dp.id_producto
JOIN   categoria c ON c.id_categoria = pr.id_categoria
WHERE  dp.eliminado = FALSE
GROUP  BY c.id_categoria, c.nombre_categoria
WITH DATA;

CREATE UNIQUE INDEX uq_mv_tp_u4_top5_cat_dia
    ON mv_tp_u4_top5_cat_dia (id_categoria);
```

Filas materializadas (BLOQUE 4): **2**.

**Desactualización entre refrescos:** `CURRENT_DATE` se evalúa en el momento del
`REFRESH`, no al leer. Si el último refresh fue ayer, la vista muestra ayer. La
frecuencia de actualización (ej.: cada hora durante el horario operativo, o
antes de abrir el panel) **debe acordarse con quien mantiene el panel** y
quedará documentada acá. La vista no debe usarse para operaciones
transaccionales ni totales de pedidos activos.

### 3.5 MEDICIÓN 2 — lectura de la vista (después)

La lectura usa `EXPLAIN ANALYZE` (no solo `EXPLAIN`) para producir
Execution Time y plan real en DBeaver:

```sql
EXPLAIN ANALYZE
SELECT id_categoria, nombre_categoria, monto_vendido
FROM   mv_tp_u4_top5_cat_dia
ORDER  BY monto_vendido DESC
LIMIT  5;
```

`BLOQUE 7`:

| # | Consulta | Execution Time | Nodo dominante |
|---|---|---|---|
| 2 | Lectura de la vista materializada | **1,561 ms** | `Seq Scan` sobre la vista, seguido de `Sort` y `Limit` |

### 3.6 Comparación antes / después

| Métrica | Antes (4 tablas) | Después (vista) | Mejora |
|---|---|---|---|
| Execution Time | **4,335 ms** | **1,561 ms** | **2,8 veces** |
| Acceso y procesamiento | `Bitmap Heap Scan` en pedido, `Nested Loop`, agregación y ordenamiento | `Seq Scan` de 2 filas materializadas, ordenamiento y límite | — |

La mejora observada es de una sola ejecución por consulta. Había **dos detalles
de hoy y dos categorías resultantes**, así que no se extrapola el factor 2,8 a
una jornada con muchas ventas ni se atribuye toda la diferencia al diseño:
la caché y el estado de ejecución también pueden influir.

### 3.7 Auditoría de equivalencia (EXCEPT bidireccional)

Los EXCEPT se ejecutan **inmediatamente después de crear y poblar la vista**
(BLOQUES 5 y 6 del script) y **antes** de medir o insertar datos nuevos, para
que la comparación no quede contaminada por cambios posteriores. Comparan la
agregación directa (sin `LIMIT`, mismo `GROUP BY`) contra la vista, en ambas
direcciones:

| Dirección | Resultado |
|---|---|
| A — agregación directa EXCEPT vista | **0 filas** |
| B — vista EXCEPT agregación directa | **0 filas** |

### 3.8 Estrategia de REFRESH

| Situación | Comando |
|---|---|
| Primer populate | `CREATE MATERIALIZED VIEW ... WITH DATA` (ya incluido) |
| Refrescos posteriores | `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tp_u4_top5_cat_dia;` (comentado en BLOQUE 8) |

Como política propuesta para el panel se plantea un refresco periódico durante
el horario operativo, por ejemplo cada hora. Esa frecuencia define el retraso
máximo esperado y debe ajustarse si el negocio necesita datos más recientes.

---

## 4. Herramientas de IA utilizadas (DUIA)

| Herramienta | Para qué se usó | Qué se aceptó | Qué se corrigió o descartó y por qué |
|---|---|---|---|
| Kiro | Especificar el análisis y las pruebas en `specs/tp_u4/plan_fnbc_desnormalizacion.md` | Dependencias, clausuras, dos claves candidatas y descomposición R1/R2 | Su primera versión agregó atributos ajenos a la consigna y obtuvo una clave incorrecta. Se corrigió con la relación literal de tres atributos. |
| OpenCode | Preparar los dos scripts SQL y el borrador de este informe | Tablas originales y descompuestas, vista, pruebas `EXCEPT` y vista materializada | Se conservaron los IDs literales con claves `BIGINT` explícitas; el caso de prueba pasó a `sp_crear_pedido`, se corrigió el `EXPLAIN ANALYZE` de la vista y se dejaron vacías las mediciones hasta ejecutarlas. |
| Codex | Revisar los scripts y completar el informe con resultados reales | Comparación contra la tabla original y lectura crítica de ambos planes | Se evitó afirmar que la consulta directa había barrido 400.000 detalles: el plan real usó los índices de fecha y pedido y procesó solo dos. |

**Nota de método:** Kiro y OpenCode redactaron el plan y los scripts. Las
ejecuciones y mediciones indicadas arriba se hicieron manualmente en DBeaver
sobre `foodstore_tp_u4` y se incorporaron al informe después de verificarlas.

---

## 5. Conclusiones

- **Parte 1:** `control_lote_almacen` viola FNBC por DF2. La descomposición
  en R1 y R2 tiene unión sin pérdida: la vista reprodujo las tres filas
  originales y ambos `EXCEPT` devolvieron cero. DF1 no queda preservada
  automáticamente como restricción local de R1 o R2.
- **Parte 2:** para las dos ventas de prueba del día, la lectura del resumen
  materializado tardó 1,561 ms frente a 4,335 ms de la consulta directa. Las
  dos direcciones de la auditoría devolvieron cero filas. La vista requiere
  refrescos periódicos y puede quedar desactualizada entre ellos.

---

## Anexo — Fragmentos de las salidas reales de EXPLAIN ANALYZE

**Consulta directa, bloque 2.** El acceso empezó por `pedido` mediante
`idx_pedido_fecha` (una fila real), luego buscó dos detalles por
`detalle_pedido_id_pedido_id_producto_key` y unió producto y categoría. El
resultado se agrupó y ordenó:

```text
Bitmap Index Scan on idx_pedido_fecha         rows=1
Index Scan on detalle_pedido...key            rows=2
Nested Loop                                    rows=2
GroupAggregate                                rows=2
Sort                                          rows=2
Buffers: shared hit=16 read=2
Execution Time: 4.335 ms
```

**Vista materializada, bloque 7.** El plan leyó dos filas ya resumidas y
aplicó el orden y el límite:

```text
Seq Scan on mv_tp_u4_top5_cat_dia             rows=2
Sort (quicksort, Memory: 25kB)                rows=2
Limit                                         rows=2
Execution Time: 1.561 ms
```

Los planes completos se obtuvieron en DBeaver con los comandos `EXPLAIN`
incluidos en `sql/tp_desnormalizacion_top_categorias.sql`.

---

**Entregables (repo):** `sql/tp_fnbc_control_lote.sql`, `sql/tp_desnormalizacion_top_categorias.sql`,
`docs/tp_u4/informe_tp_u4.md`.
