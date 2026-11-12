# FoodStore Database Project

Proyecto de datos **FoodStore** sobre PostgreSQL 17, con prácticas documentales en MongoDB y una base local SQLite para la tablet. PostgreSQL es la fuente de verdad de pedidos y stock.

---

## Requisitos Previos

- **PostgreSQL 16 o superior** (las pruebas documentadas se hicieron con PostgreSQL 17).
- **DBeaver** para ejecutar los scripts y las pruebas PostgreSQL. Para las otras unidades se usaron MongoDB Compass y SQLite.

---

## 1. Creación de la Base de Datos

El primer renglón de `sql/schema.sql` contiene este comando. Ejecutarlo **una sola vez**, conectado a la base administrativa `postgres`:

```sql
CREATE DATABASE FoodStore;
```

> **Nota:** Al no estar entre comillas, PostgreSQL guarda el nombre como `foodstore`. Conectarse a `foodstore` y ejecutar el resto de `sql/schema.sql`, **sin repetir** su primera línea.

---

## 2. Orden de Ejecución de los Scripts

La carga inicial en una base vacía sigue este orden. Los scripts de consultas y pruebas se ejecutan después, de forma selectiva, sobre una copia de trabajo porque varios modifican datos:

| Paso | Archivo | Descripción |
| :--: | :--- | :--- |
| **1** | `sql/schema.sql` (desde la línea 3) | Crea los tipos enumerados (`rol`, `estado_pedido`, `forma_pago`), las tablas relacionales (`categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`) y los índices. |
| **2** | `sql/Objects.sql` | Define vistas, funciones, triggers y el procedimiento `sp_crear_pedido`. |
| **3** | `sql/data.sql` | Inserta los datos iniciales de prueba. |
| **Pruebas** | `sql/queries.sql` | Contiene consultas y también `INSERT`, `UPDATE` y `CALL`; ejecutar solo las secciones necesarias sobre una copia. |

---

## 3. Cómo Reproducir las Pruebas

Para validar restricciones y lógica de negocio, usar una **copia de trabajo** de `foodstore`. Los ejemplos con `CALL` o `UPDATE` alteran datos; envolverlos en una transacción cuando se quiera revertirlos.

### A. Pruebas de Integridad y Triggers Automáticos
1. **Comprobar cálculo automático de subtotales y total:**
   ```sql
   -- Consulta un pedido para verificar que el total se calculó automáticamente por trigger
   SELECT * FROM v_pedidos_resumen WHERE id_pedido = 1;
   SELECT * FROM v_pedido_detalle WHERE id_pedido = 1;
   ```

2. **Verificar borrado lógico (*Soft Delete*):**
   ```sql
   -- Las vistas no deben mostrar registros con eliminado = TRUE
   SELECT * FROM v_categorias_vigentes;  -- No incluye 'Ensaladas'
   SELECT * FROM v_productos_vigentes;   -- No incluye 'Especial' ni 'Jugo de Naranja'
   ```

---

### B. Pruebas de Transaccionalidad y Manejo de Stock (`sp_crear_pedido`)

1. **Creación exitosa de un pedido compuesto:**
   ```sql
   CALL sp_crear_pedido(
       2, -- id_usuario (Ana Gomez)
       'EFECTIVO',
       '[{"producto_id": 1, "cantidad": 2}, {"producto_id": 13, "cantidad": 1}]'::jsonb
   );
   
   -- Verificar que el stock se descontó correctamente en los productos 1 y 13
   SELECT id_producto, nombre_producto, stock FROM producto WHERE id_producto IN (1, 13);
   ```

2. **Prueba de fallo por Stock Insuficiente (Rollback automático):**
   ```sql
   -- Intentar pedir más unidades de las disponibles (ej. 9999 empanadas)
   CALL sp_crear_pedido(
       2,
       'TARJETA',
       '[{"producto_id": 5, "cantidad": 9999}]'::jsonb
   );
   -- RESULTADO ESPERADO: Excepción 'Stock insuficiente...', la transacción completa se revierte y no se crea el pedido.
   ```

3. **Prueba de fallo por Producto no disponible / dado de baja:**
   ```sql
   -- Intentar comprar un producto descontinuado o eliminado (id_producto = 4)
   CALL sp_crear_pedido(
       2,
       'TARJETA',
       '[{"producto_id": 4, "cantidad": 1}]'::jsonb
   );
   -- RESULTADO ESPERADO: Excepción 'Producto 4 inexistente o eliminado'.
   ```

---

### C. Pruebas de Consultas Analíticas (queries.sql)
Abre y ejecuta las consultas de la sección final de `queries.sql` para comprobar:
* **Top 5 productos más vendidos:** Agregación por volumen de ventas.
* **Facturación mensual por categoría:** Agrupación y acumulados temporales.
* **Ranking de usuarios:** Función de ventana analítica (`RANK() OVER (...)`).
* **Detección de productos sin ventas:** Verificación con `LEFT JOIN ... WHERE id_detalle IS NULL`.

---

## 4. TP5 — Índices y vistas

**Base de trabajo:** `foodstore_tp5`, creada como copia de `foodstore_tp3`.

### Orden de ejecución (una sola vez)

Ejecutar, en este orden, sobre `foodstore_tp5`:

1. `sql/indices_tp5.sql` — tres índices parciales selectivos.
2. `sql/views_tp5.sql` — tres vistas de reporte nuevas.
3. `sql/vista_materializada_tp5.sql` — vista materializada de facturación + índice único.

### Scripts de verificación

- `sql/test_vistas_tp5.sql` — verificaciones de lectura de las vistas (EXCEPT de equivalencia).
- `sql/test_vista_materializada_tp5.sql` — consultas de lectura, `EXPLAIN ANALYZE` y EXCEPT de equivalencia de la vista materializada.

### Índices creados (selectivos, parciales)

1. `idx_pedido_cancelado_fecha_vig` — `pedido (fecha DESC)` donde `eliminado = FALSE AND estado = 'CANCELADO'`.
2. `idx_producto_no_disponible_nombre_vig` — `producto (nombre_producto ASC)` donde `eliminado = FALSE AND disponible = FALSE`.
3. `idx_detalle_cantidad_excepcional_vig` — `detalle_pedido (cantidad DESC, id_detalle ASC)` donde `eliminado = FALSE AND cantidad >= 5`.

### Vistas de reporte nuevas

1. `v_tp5_productos_categoria` — catálogo de productos vigentes con categoría.
2. `v_tp5_pedidos_usuario` — pedidos con identidad del usuario (sin `contrasena`, `celular` ni `rol`).
3. `v_tp5_detalle_pedido_productos` — detalle de pedidos conservando productos históricos eliminados.

### Vista materializada

`mv_tp5_facturacion_categoria_mes` — resume la facturación por categoría y mes (consultas `detalle_pedido`/`pedido`/`producto`/`categoria`) para lecturas de reporte en lugar de repetir los joins y la agregación.

**Refresco manual** (por lotes o diario, nunca por cada `INSERT`):

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_tp5_facturacion_categoria_mes;
```

Requiere el índice único `uq_mv_tp5_facturacion_categoria_mes` (creado en `sql/vista_materializada_tp5.sql`) y no debe ejecutarse por cada `INSERT`.

### Documentación de mediciones

- `docs/tp5/informe_mediciones_tp5.md` — resultados antes/después de índices, vistas y vista materializada, y las propuestas descartadas.
- `docs/tp5/duia_tp5.md` — registro de uso de herramientas (Kiro para specs, OpenCode para implementación y documentación) y validación manual en DBeaver.

---

## 5. Organización del repositorio

Los scripts ejecutables se conservan en `sql/`. La documentación y las especificaciones se separan por entrega para que no interfieran con el orden de ejecución de la base.

```text
docs/
├── modelo/  — modelo ER e informe base del TP1
├── tp2/     — informes, protocolo y DUIA de integridad/concurrencia
├── tp3/     — informe y DUIA de carga masiva y optimización
├── tp4/     — informe y DUIA de análisis de planes
├── tp5/     — informe y DUIA de índices, vistas y vista materializada
├── tp_u4/   — FNBC y desnormalización controlada
├── tp7/     — modelo y consultas MongoDB
├── tp8/     — SQLite, semáforo e integración
└── tpi/     — informes, DUIA y auditorías de las entregas integradoras

specs/
├── tp2/     — especificación de restricciones
├── tp4/     — especificación de consultas analíticas
├── tp5/     — especificaciones de índices y vistas
├── tp_u4/   — plan de FNBC y desnormalización
└── tpi/     — auditoría y evidencia de normalización del integrador
```

Los entregables en PDF se ubican junto con la documentación de su respectivo TP. El informe técnico de la primera entrega integradora está en `docs/tpi/TPI_FoodStore_Primera_Entrega_Parcial.pdf`.

---

## 6. TP8 - Tablet SQLite y sincronización simulada

**Base central de pruebas:** `foodstore_u8`, creada como copia de `foodstore`. **Base local:** `movil/foodstore_movil.db` (SQLite 3.37+). La tablet nunca crea pedidos ni cambia stock en PostgreSQL; `SIMULADO_APROBADO` es solo un resultado de simulación.

### Crear desde cero

1. En PostgreSQL, conectado a la base `postgres` y sin conexiones abiertas a `foodstore`, crear `foodstore_u8` con `CREATE DATABASE foodstore_u8 WITH TEMPLATE foodstore OWNER postgres;`. Si ya existe, no repetir la creación.
2. Conectarse a `foodstore_u8` y ejecutar `postgresql/v_snapshot_movil.sql`.
3. Exportar `v_snapshot_movil` a `movil/servidor_snapshot.csv` con encabezados y separador coma. Al exportar desde DBeaver, convertir `disponible` y `eliminado` explícitamente a `'t'`/`'f'`, porque los scripts SQLite esperan esos valores. La consulta usada figura debajo.
4. Crear una base SQLite vacía y ejecutar `movil/schema_sqlite.sql`. Verificar `PRAGMA foreign_keys;` = `1` en cada conexión que vaya a escribir.
5. Vaciar `snapshot_servidor`, importar el CSV **en la tabla existente**, y ejecutar `movil/cargar_snapshot.sql` para actualizar `producto_cache` mediante UPSERT. No usar `INSERT OR REPLACE`, que puede romper referencias de los ítems.
6. Ejecutar una sola vez `movil/datos_casos.sql` y `movil/pruebas_sqlite.sql`. Los intentos inválidos de C7 están comentados: ejecutarlos por separado, observar el error y cerrar cada transacción con `ROLLBACK`.
7. En `foodstore_u8`, cambiar el precio del producto elegido para C2 y dar de baja lógicamente el elegido para C4. Exportar otra instantánea y repetir el paso 5. La copia inicial puede conservarse como `movil/servidor_snapshot_inicial.csv`.
8. Ejecutar `movil/semaforo.sql`. Verificar C2=`CONFLICTO`, C3 y C4=`RECHAZADO`, C5 y C6=`SIMULADO_APROBADO`. Para C2, aceptar el precio nuevo en el ítem, crear una solicitud **con otro UUID** y ejecutar de nuevo el semáforo.
9. Para C6, **después** de que el semáforo haya evaluado la solicitud, ejecutar por separado el `INSERT` duplicado comentado en `movil/datos_casos.sql`. Debe fallar por `cola_sync.solicitud_uuid`; consultar luego la misma fila para comprobar que conserva el estado y que su cantidad sigue siendo uno.
10. En PostgreSQL, comprobar el conteo de `pedido` y el stock. La simulación no debe haber creado una venta ni descontado unidades. El informe y la bitácora están en `docs/tp8/`; los requisitos previos de Kiro están en `docs/kiro/tp8/`.

Consulta de exportación desde DBeaver:

```sql
SELECT producto_id, nombre, precio_centavos, stock,
       CASE WHEN disponible THEN 't' ELSE 'f' END AS disponible,
       CASE WHEN eliminado THEN 't' ELSE 'f' END AS eliminado,
       to_char(capturado_en AT TIME ZONE 'UTC',
               'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS capturado_en
FROM v_snapshot_movil
ORDER BY producto_id;
```

Si se usa la consola `sqlite3`, la secuencia básica es:

```text
sqlite3 movil/foodstore_movil.db < movil/schema_sqlite.sql
sqlite3 movil/foodstore_movil.db "DELETE FROM snapshot_servidor;"
sqlite3 movil/foodstore_movil.db ".import --csv --skip 1 movil/servidor_snapshot.csv snapshot_servidor"
sqlite3 movil/foodstore_movil.db < movil/cargar_snapshot.sql
sqlite3 movil/foodstore_movil.db < movil/datos_casos.sql
sqlite3 movil/foodstore_movil.db < movil/pruebas_sqlite.sql
sqlite3 movil/foodstore_movil.db < movil/semaforo.sql
```

El CSV debe importarse con siete columnas en este orden: `producto_id`, `nombre`, `precio_centavos`, `stock`, `disponible`, `eliminado`, `capturado_en`. `schema_sqlite.sql` crea `snapshot_servidor` con esos nombres y tipos, por lo que no debe usarse la opción de crear tabla nueva al importar.

---

## 7. Segunda entrega parcial del TPI (unidades 4 a 8)

La [auditoría de cobertura](docs/tpi/auditoria_segunda_entrega.md) relaciona los 14 criterios de la consigna con archivos y resultados reales. El [informe técnico](docs/tpi/informe_tpi_segunda_entrega.md) y la [DUIA integradora](docs/tpi/duia_tpi_segunda_entrega.md) consolidan las unidades 4 a 8. Los dos documentos están en borrador hasta completar los pendientes indicados en la auditoría.

| Unidad | Scripts y datos | Evidencia |
| --- | --- | --- |
| 4 - FNBC y desnormalización | `sql/tp_fnbc_control_lote.sql`, `sql/tp_desnormalizacion_top_categorias.sql` | `specs/tp_u4/plan_fnbc_desnormalizacion.md`, `docs/tp_u4/informe_tp_u4.md` |
| 5 - Seguridad y auditoría | `sql/roles.sql`, `sql/auditoria_test.sql`, `sql/autenticacion_u5.sql`, `sql/simulacro_incidente.sql`, `sql/usuario_anon.sql` | `BITACORA.md`, `docs/informe_auditoria.md`, `docs/informe_incidente.md` |
| 6 - Mantenimiento | `scripts/backup_foodstore.ps1`, `scripts/restore_test.ps1`, `sql/health_check.sql`, `sql/maintenance.sql` | `informe_u6.pdf` |
| 7 - Documental | `mongodb/pedidos_u7.json`, `mongodb/consultas_mongodb.js`, `sql/consultas_postgresql_u7.sql` | `docs/tp7/informe_tp7.md` |
| 8 - Tablet | `postgresql/v_snapshot_movil.sql`, `movil/` | `docs/kiro/tp8/`, `docs/tp8/informe_tp8.md`, `docs/tp8/bitacora_ia.md` |

Cada unidad usa una copia o base de pruebas propia. No ejecutar estos scripts secuencialmente sobre `foodstore`: varios crean objetos, modifican datos o configuran el servidor. El informe de cada unidad describe su base, el orden y la validación realizada.
