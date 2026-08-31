# DUIA — Parte 1: Restricciones de integridad

**Herramienta:** OpenCode — modelo/proveedor: **Big Pickle**

## Datos generales

- **Materia:** Base de Datos II
- **Trabajo práctico:** TP2 — FoodStore
- **Parte:** 1 — Restricciones de integridad
- **Base de datos de trabajo:** `foodstore_tp2` (PostgreSQL 17)
- **Fecha:** 2026-08-31

---

## Spec y prompt utilizados

La decisión de negocio se documentó primero en `spec_restricciones.md`.

Prompt principal de implementación enviado a OpenCode:

> Plan aprobado. Implementalo con estas condiciones finales:
>
> - Crear únicamente `sql/restricciones.sql`, `sql/test_restricciones.sql` y `duia_parte1.md`.
> - No modificar `schema.sql`, `Objects.sql`, `data.sql`, `queries.sql` ni `transacciones.sql`.
> - En las pruebas que generen una excepción esperada, indicar que `ROLLBACK` debe ejecutarse en la misma conexión/sesión de DBeaver; no sugerir una pestaña nueva.
> - Mantener cada `WITH cat_disponible` junto al `UPDATE` que lo usa, dentro de la misma sentencia.
> - `duia_parte1.md` debe incluir el campo "Herramienta: OpenCode" y todos los campos exigidos por la consigna.
> - No ejecutar ningún script sobre la base de datos.
> - No hacer commits.
>
> Al terminar, mostrá un resumen y el diff de los tres archivos creados.

---

## Qué generó OpenCode

- `sql/restricciones.sql`: dos funciones PL/pgSQL y dos triggers para las reglas definidas.
- `sql/test_restricciones.sql`: casos válidos e inválidos, aislados con `BEGIN` y `ROLLBACK`.
- `duia_parte1.md`: plantilla inicial de esta declaración.

---

## Qué se aceptó sin modificaciones

- La lógica final de `fn_check_estado_transition()` y `trg_check_estado_transition`.
- La lógica final de `fn_check_categoria_baja_logica()` y `trg_check_categoria_baja_logica`.
- La decisión de crear scripts nuevos, sin alterar los scripts originales de Semana 1.

---

## Qué se modificó y por qué

- Se corrigió la suposición inicial de que `schema.sql` estaba vacío; el archivo fue restaurado antes de implementar las restricciones.
- Se reemplazaron los marcadores genéricos `X` de las pruebas por pedidos existentes del seed data para que los casos fueran ejecutables.
- Las pruebas de bajas válidas ahora crean categorías y productos temporales dentro de la transacción, porque los datos existentes no incluían categorías activas sin productos vigentes.
- En la prueba del producto temporal se agregó el filtro por categoría temporal para evitar afectar accidentalmente otro producto con el mismo nombre.
- Se documentó que el respaldo se realiza desde DBeaver y que, ante una excepción esperada, `ROLLBACK` debe ejecutarse en la misma sesión.

---

## Resultados reales de las pruebas

### Regla 1 — Transiciones de estado del pedido

Antes de probar, se determinó un `id_pedido` con estado `PENDIENTE` (y otro `CONFIRMADO`) mediante consulta previa.

| # | Escenario | Estado actual | Nuevo estado | Resultado esperado | Resultado real | OK? |
|---|-----------|---------------|--------------|--------------------|----------------|-----|
| 1 | PENDIENTE → CONFIRMADO | PENDIENTE | CONFIRMADO | ✅ Válido | Permitido; `ROLLBACK` aplicado | Sí |
| 2 | PENDIENTE → CANCELADO | PENDIENTE | CANCELADO | ✅ Válido | Permitido; `ROLLBACK` aplicado | Sí |
| 3 | CONFIRMADO → TERMINADO | CONFIRMADO | TERMINADO | ✅ Válido | Permitido; `ROLLBACK` aplicado | Sí |
| 4 | CONFIRMADO → CANCELADO | CONFIRMADO | CANCELADO | ✅ Válido | Permitido; `ROLLBACK` aplicado | Sí |
| 5 | PENDIENTE → TERMINADO | PENDIENTE | TERMINADO | ❌ Excepción | `Transición de estado inválida: "PENDIENTE" -> "TERMINADO"` | Sí |
| 6 | CONFIRMADO → PENDIENTE | CONFIRMADO | PENDIENTE | ❌ Excepción | `Transición de estado inválida: "CONFIRMADO" -> "PENDIENTE"` | Sí |
| 7 | TERMINADO → CONFIRMADO | TERMINADO | CONFIRMADO | ❌ Excepción | `Estado final "TERMINADO" no puede cambiar a "CONFIRMADO"` | Sí |
| 8 | CANCELADO → PENDIENTE | CANCELADO | PENDIENTE | ❌ Excepción | `Estado final "CANCELADO" no puede cambiar a "PENDIENTE"` | Sí |
| 9 | Mismo estado, sin cambio real | PENDIENTE | PENDIENTE | ✅ Permitido | Permitido; `ROLLBACK` aplicado | Sí |
| 10 | Cambio de otra columna (forma_pago) | — | — | ✅ Trigger no se activa | Permitido; `ROLLBACK` aplicado | Sí |

### Regla 2 — Baja lógica de categorías

| # | Escenario | Resultado esperado | Resultado real | OK? |
|---|-----------|--------------------|----------------|-----|
| 1 | Baja de categoría sin productos vigentes (con `RETURNING`) | ✅ Válido | Categoría temporal dada de baja; `ROLLBACK` aplicado | Sí |
| 2 | Baja de categoría con productos vigentes | ❌ Excepción | `No se puede eliminar la categoría 1: tiene productos vigentes asociados` | Sí |
| 3 | Reactivación de categoría eliminada (TRUE → FALSE) | ✅ Permitido | Permitido; `ROLLBACK` aplicado | Sí |
| 4 | Baja de categoría con todos sus productos eliminados | ✅ Válido | Categoría temporal dada de baja; `ROLLBACK` aplicado | Sí |

---

## Verificación realizada

1. Se generó un respaldo de `foodstore_tp2` antes de aplicar el DDL.
2. `restricciones.sql` se ejecutó primero dentro de `BEGIN` y `ROLLBACK`, sin errores.
3. Se repitió la aplicación dentro de `BEGIN` y `COMMIT`, sin errores.
4. Se ejecutaron casos válidos e inválidos sobre `foodstore_tp2`; las pruebas válidas se revirtieron y las excepciones esperadas se confirmaron.

## Comandos / procedimiento de backup previo

1. DBeaver → conexión a `foodstore_tp2`.
2. Botón derecho sobre la base → Tools → Backup.
3. Formato: **Custom**.
4. Destino: `backups/foodstore_tp2_pre_restricciones.dump`.
5. Resultado: backup generado correctamente.

---

## Dudas y observaciones

Las excepciones esperadas devuelven SQLSTATE `P0001` porque fueron lanzadas explícitamente con `RAISE EXCEPTION` desde funciones PL/pgSQL. Después de cada una se ejecutó `ROLLBACK` en la misma sesión de DBeaver.

---

## Revisión final y publicación

1. `git diff` — revisión línea por línea de los archivos creados/modificados.
2. `git add` — agregar `spec_restricciones.md`, `sql/restricciones.sql`, `sql/test_restricciones.sql` y `duia_parte1.md`.
3. `git commit` — mensaje descriptivo.
4. `git push` — subir al repositorio remoto.
