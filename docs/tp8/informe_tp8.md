# TP8 FoodStore - Base de la tablet e integración

**Bases de Datos II - Unidad 8**  
**Integrantes:** Franco Sampieri, Mauro Di Pietro, Tomas Martinez y Renzo Victoria  
**Motores:** PostgreSQL 17, SQLite 3.50.4 y MongoDB (Unidad 7)

## 1. La base de la tablet

La tablet conserva una copia pequeña del catálogo para trabajar sin señal. Viajan `producto_id`, nombre, precio en centavos, stock visto, disponibilidad, marca de baja y fecha de captura. No viajan contraseñas, mails, celulares, imágenes ni el historial de ventas. El stock de la tablet es orientativo: PostgreSQL sigue siendo la fuente de verdad del precio, el stock y los pedidos confirmados.

En `movil/schema_sqlite.sql` se crearon las cuatro tablas pedidas (`producto_cache`, `pedido_borrador`, `item_borrador`, `cola_sync`) y la tabla auxiliar permanente `snapshot_servidor`. Son tablas `STRICT`, con claves foráneas activadas al abrir SQLite, restricciones `CHECK` y precios expresados como enteros en centavos. El índice parcial de `cola_sync` permite un solo envío pendiente por borrador; una solicitud resuelta puede convivir con un nuevo intento.

La primera instantánea de `foodstore_u8` trajo 25 productos, incluidos tres dados de baja. La consulta local `v_catalogo_disponible` mostró 21 productos antes de la segunda instantánea y 20 después. El catálogo se consultó sin conectarse a PostgreSQL (C1).

El script `movil/pruebas_sqlite.sql` guardó borrador, ítem y solicitud dentro de `BEGIN`/`COMMIT`. Otro borrador insertado dentro de `BEGIN`/`ROLLBACK` dejó cero filas. En C7, la cantidad cero produjo `CHECK constraint failed: cantidad > 0` y el producto inexistente produjo `FOREIGN KEY constraint failed`; tras cada `ROLLBACK` no quedó ninguna fila nueva.

## 2. Instantánea y sincronización simulada

La vista PostgreSQL `v_snapshot_movil` publica el catálogo con precio en centavos y la baja lógica del producto o de su categoría. El CSV se importó a `snapshot_servidor`; `movil/cargar_snapshot.sql` actualizó `producto_cache` mediante UPSERT, conservando los ítems que referencian productos dados de baja. La copia inicial se conservó como `movil/servidor_snapshot_inicial.csv`.

Entre las dos instantáneas, en la base de **pruebas** se subió la Muzzarella de $2.400 a $2.500 y se dio de baja lógicamente la Fugazzeta. Los 25 IDs y todos los valores de stock permanecieron iguales en ambos CSV. El semáforo comparó los ítems con la segunda instantánea y guardó estos resultados en SQLite:

| Caso | Resultado observado | Comprobación |
| --- | --- | --- |
| C2, precio | `CONFLICTO` | Producto 1: 240000 centavos vistos, 250000 actuales. Tras aceptar el precio y crear una nueva solicitud, esta dio `SIMULADO_APROBADO`; la anterior quedó en `CONFLICTO`. |
| C3, stock | `RECHAZADO` | Se solicitaron 16 unidades del producto 2 y la instantánea indicaba 15. |
| C4, baja lógica | `RECHAZADO` | El producto 3 quedó marcado como eliminado. No aparece en `v_catalogo_disponible`, pero su ítem del borrador sigue guardado. |
| C5, sin cambios | `SIMULADO_APROBADO` | Coincidieron precio, disponibilidad y stock. |
| C6, UUID repetido | Error de unicidad | Después de evaluar el envío, repetir su `solicitud_uuid` produjo `UNIQUE constraint failed: cola_sync.solicitud_uuid`. Quedó una sola fila y el estado previo no cambió. |

Volver a ejecutar `movil/semaforo.sql` solo toma las solicitudes `PENDIENTE`. `SIMULADO_APROBADO` representa una validación local, **no una venta**: no se llamó a `sp_crear_pedido` ni se descontó stock. En un sistema real, PostgreSQL necesitaría registrar el UUID de solicitud con una clave única en la misma transacción que crea el pedido.

La comprobación final en `foodstore_u8` devolvió **21 pedidos y stock total 785**. El stock total coincide con ambas instantáneas y el conteo de pedidos coincide con la copia inicial: la simulación no creó una venta ni descontó unidades.

## 3. Integración y mantenimiento

| Motor | Qué guarda en este proyecto | Quién decide |
| --- | --- | --- |
| PostgreSQL | Catálogo oficial, usuarios, stock y pedidos | Es la fuente de verdad de precios, stock y ventas. |
| MongoDB | Cinco documentos de pedidos con líneas embebidas, preparados en la Unidad 7 para consultas documentales | Es una copia de lectura; no confirma pedidos ni decide stock. |
| SQLite | Catálogo copiado, borradores, ítems y cola de solicitudes de la tablet | Trabaja sin señal y propone pedidos; conserva estados de simulación. |

Como continuidad de la Unidad 6, el respaldo principal es el de PostgreSQL en formato custom, con comprobación de lectura y restauración de prueba. También se conserva la exportación de los documentos de MongoDB y se protegen los archivos SQLite que contengan borradores pendientes; el catálogo copiado puede volver a descargarse. Si PostgreSQL se restaura desde un respaldo antiguo, las tablets deben invalidar su instantánea, descargar otra y revisar las solicitudes pendientes antes de cualquier reenvío. Los conflictos y rechazos los revisa el responsable del turno tras cada sincronización y al cierre del día.

## 4. Revisión con IA

Kiro produjo los cuatro requisitos EARS y el diseño previo. OpenCode generó los scripts a partir de esas tareas. Codex se usó para revisar el SQL y ejecutar pruebas sobre SQLite; las propuestas incorrectas se corrigieron antes de usar los archivos. El detalle está en `docs/tp8/bitacora_ia.md`.

OpenCode, en agente Plan, revisó por lectura estática los scripts de las unidades 1 a 8. El equipo contrastó sus propuestas con el código y las pruebas. Esta es la decisión sobre **cada hallazgo** recibido:

| Hallazgo | Decisión y fundamento |
| --- | --- |
| H1 - mover un detalle deja el total de origen (U1) | **Aceptado, corregido y probado.** `trg_total_upd` recibe solo la tabla `NEW`; la nueva `fn_set_subtotal` prohíbe cambiar `id_pedido` o `id_producto` de un detalle. El intento de trasladarlo en `foodstore_u8` produjo el error esperado. |
| H2 - precio unitario arbitrario en un INSERT directo (U1) | **Aceptado, reproducido y corregido.** Antes de cambiar la función, un INSERT con precio `0.01` devolvió `precio_unitario = 0.01` y `subtotal = 0.01` para el nuevo pedido 22. Tras aplicar la función en `foodstore_u8`, la misma prueba devolvió `2500.00` y `5000.00`: ahora toma el precio real del producto. Actualizar la cantidad produjo un subtotal coherente con `cantidad * precio_unitario`. Las pruebas se hicieron dentro de transacciones con `ROLLBACK`. |
| H3 - categoría eliminada con producto activo (U1/2) | **Aceptado como hueco de integridad.** La baja de categoría se restringe, pero una inserción o reactivación posterior del producto no comprueba la categoría. El ejemplo de OpenCode usa un ID de producto supuesto: debe sustituirse por el `RETURNING` real al probarlo. |
| H4 - índice parcial de no disponibles inaplicable (U3) | **Descartado como conclusión general; comentario corregido.** El plan real de TP5 mostró `Index Scan` usando ese índice al medir la consulta con ambos filtros. El comentario de `sql/indices_tp5.sql` ahora incluye `eliminado = FALSE`. |
| H5 - dos definiciones de producto vigente (U1) | **Aceptado.** `HU-PROD-01` no filtra `categoria.eliminado`, mientras `v_productos_vigentes` sí. Conviene alinear la consulta. |
| H6 - borrador vacío queda pendiente (U8) | **Corregido y comprobado.** Antes quedaba `PENDIENTE` con motivo `NULL`. OpenCode cambió el JOIN de ítems y, al probar el archivo corregido en memoria, pasó a `RECHAZADO` con motivo `Borrador sin ítems`; los estados previos C2-C6 no cambiaron. |
| m1 - chequeo de salud con nombre fijo de base (U6) | **Aceptado como limitación de reutilización.** El script apunta expresamente a `foodstore`; sobre otra copia, las consultas de actividad seguirían mirando la base original. |
| m2 - restauración con conteos fijos (U6) | **Aceptado como limitación.** Sirve para el respaldo inicial documentado, pero no valida sin ajuste un respaldo tomado tras cambiar los datos. |
| D1 - falta un error SERIALIZABLE (U1) | **Descartado.** La sesión A del ejemplo solo lee y conserva su snapshot; que haga `COMMIT` en ese escenario no contradice el aislamiento. |
| D2 - `ORDER BY` dentro de CTE usadas con `EXCEPT` (U3) | **Descartado como defecto funcional.** `EXCEPT` compara conjuntos; las seis equivalencias de vistas del TP5 dieron cero filas. Solo es impreciso el comentario que atribuye estabilidad al orden interno. |

Los tres casos desarrollados para la entrega son **H2 (U1), H4 (U3) y H6 (U8)**. H4 se descarta como conclusión general con evidencia del plan: la consulta realmente medida incluía `eliminado = FALSE`, usó `idx_producto_no_disponible_nombre_vig` y bajó de **31,581 ms a 2,767 ms**. H6 se reprodujo y corrigió sin cambiar C2-C6. H2 quedó demostrado por la fila `22 | 0.01 | 0.01`; tras la corrección, el mismo intento produjo `2500.00 | 5000.00`. También se probó el cambio de cantidad y se confirmó el rechazo al traslado de un detalle (H1).
