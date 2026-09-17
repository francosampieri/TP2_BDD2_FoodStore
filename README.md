# FoodStore Database Project

Base de datos relacional para el sistema de gestión de pedidos gastronómicos **FoodStore**, implementada sobre **PostgreSQL**.

---

## Requisitos Previos

- **PostgreSQL** 14 o superior instalado.
- Cliente SQL: **pgAdmin 4**, **DBeaver**, **VS Code (extensión PostgreSQL)** o la terminal interactiva **`psql`**.

---

## 1. Creación de la Base de Datos

Ejecuta el siguiente comando en tu cliente SQL o terminal:

```sql
CREATE DATABASE "FoodStore";
```

> **Nota:** Conéctate a la base de datos recién creada (`FoodStore`) antes de ejecutar los scripts siguientes.

---

## 2. Orden de Ejecución de los Scripts

Los scripts deben ejecutarse estrictamente en el siguiente orden secuencial para garantizar la integridad referencial y las dependencias de objetos:

| Paso | Archivo | Descripción |
| :--: | :--- | :--- |
| **1** | `schema.sql` | Crea los tipos enumerados (`rol`, `estado_pedido`, `forma_pago`), las tablas relacionales (`categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`) y los índices de rendimiento. |
| **2** | `Objects.sql` | Define la lógica de negocio: vistas de consulta (`v_productos_vigentes`, `v_pedidos_resumen`, etc.), funciones auxiliares, triggers de subtotal/total y el procedimiento almacenado transaccional `sp_crear_pedido`. |
| **3** | `data.sql` | Inserta el conjunto inicial de datos de prueba: categorías, catálogo de productos, usuarios con diferentes roles, pedidos y sus respectivos detalles. |
| **4** | `queries.sql` | Contiene los casos de uso por épicas (Historias de Usuario) y las consultas analíticas de reportes. |

---

## 3. Cómo Reproducir las Pruebas

Para validar el correcto funcionamiento del modelo, las restricciones de integridad y la lógica de negocio, ejecuta las siguientes pruebas en `FoodStore`:

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

- `informe_mediciones_tp5.md` — resultados antes/después de índices, vistas y vista materializada, y las propuestas descartadas.
- `duia_tp5.md` — registro de uso de herramientas (Kiro para specs, OpenCode para implementación y documentación) y validación manual en DBeaver.
