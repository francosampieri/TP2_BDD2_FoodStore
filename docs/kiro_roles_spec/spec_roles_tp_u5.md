# Especificación de Roles y Privilegios — TP Unidad 5 Parte A

> Especificación previa a la implementación.
> No contiene DDL ejecutable. No modifica permisos existentes.
> Base de trabajo: `foodstore_tp_u4` (o copia equivalente con el esquema completo).
> Script a generar después: `sql/roles.sql`.

---

## 1. Inventario de objetos del esquema `public`

Relevado de `schema.sql`, `Objects.sql`, `views_tp5.sql` y `vista_materializada_tp5.sql`.

### 1.1 Tablas base

| Tabla | Columnas sensibles | Notas |
|---|---|---|
| `categoria` | — | Solo admins y escritura |
| `producto` | — | Lectura pública; escritura restringida |
| `usuario` | `contrasena`, `celular`, `mail` | **Alta sensibilidad** — ver conflicto §5 |
| `pedido` | `total` (calculado por trigger) | Escritura solo vía `sp_crear_pedido` |
| `detalle_pedido` | `precio_unitario`, `subtotal` (calculados por trigger) | Escritura solo vía `sp_crear_pedido` |

### 1.2 Vistas regulares (`Objects.sql`)

| Vista | Tablas que toca | Columnas expuestas |
|---|---|---|
| `v_productos_vigentes` | `producto`, `categoria` | Sin datos sensibles |
| `v_pedidos_resumen` | `pedido`, `usuario` | Expone nombre+apellido concatenado, no `contrasena` |
| `v_pedido_detalle` | `detalle_pedido`, `producto` | Sin datos sensibles |
| `v_categorias_vigentes` | `categoria` | Sin datos sensibles |

### 1.3 Vistas regulares (TP5 — `views_tp5.sql`)

| Vista | Tablas que toca | Columnas expuestas |
|---|---|---|
| `v_tp5_productos_categoria` | `producto`, `categoria` | Sin datos sensibles |
| `v_tp5_pedidos_usuario` | `pedido`, `usuario` | Expone `mail`; no expone `contrasena`, `celular`, `rol` |
| `v_tp5_detalle_pedido_productos` | `detalle_pedido`, `producto` | Sin datos sensibles |

### 1.4 Vista materializada

| Vista materializada | Columnas |
|---|---|
| `mv_tp5_facturacion_categoria_mes` | `id_categoria`, `nombre_categoria`, `mes`, `facturado` |

### 1.5 Funciones y procedimiento

| Objeto | Tipo | Firma |
|---|---|---|
| `calcular_total_pedido` | Función SQL STABLE | `(BIGINT) → NUMERIC(12,2)` |
| `fn_set_subtotal` | Función PL/pgSQL (trigger) | `() → TRIGGER` |
| `fn_recalcular_total` | Función PL/pgSQL (trigger) | `() → TRIGGER` |
| `fn_check_estado_transition` | Función PL/pgSQL (trigger) | `() → TRIGGER` |
| `fn_check_categoria_baja_logica` | Función PL/pgSQL (trigger) | `() → TRIGGER` |
| `sp_crear_pedido` | Procedimiento PL/pgSQL | `(BIGINT, forma_pago, JSONB)` |

### 1.6 Secuencias (implícitas en GENERATED ALWAYS AS IDENTITY)

Las columnas `id_*` usan secuencias internas de PostgreSQL asociadas a cada tabla.
No se otorgan permisos explícitos sobre secuencias: el acceso se controla a nivel
de tabla (INSERT/UPDATE activan la secuencia automáticamente con el permiso de tabla).

---

## 2. Roles de grupo y roles LOGIN

### 2.1 Roles de grupo (sin LOGIN)

| Rol | Propósito |
|---|---|
| `rol_app_lectura` | Lectura de catálogo y vistas de consulta general |
| `rol_app_escritura` | Creación de pedidos vía procedimiento; incluye `rol_app_lectura` |
| `rol_soporte` | Diagnóstico y consultas operativas; NO puede crear ni modificar datos de negocio |
| `rol_reportes` | Acceso exclusivo a vistas de reporte y vista materializada |

### 2.2 Roles LOGIN

| Rol | Membresías | Propósito |
|---|---|---|
| `app_web` | `rol_app_escritura` | Usuario de la aplicación web de pedidos |
| `admin_datos` | `rol_soporte`, `rol_reportes` | Administración operativa sin acceso a contraseñas |

---

## 3. Matriz de privilegios detallada

### Convenciones

- **S** = SELECT
- **I** = INSERT
- **U** = UPDATE
- **D** = DELETE
- **E** = EXECUTE
- **✗** = sin privilegio (o REVOKE explícito)
- **col(x,y)** = privilegio columna sobre columnas específicas

---

### 3.1 Esquema `public`

Todos los roles deben tener `USAGE` en el esquema `public` para poder acceder
a los objetos. Sin `USAGE`, ningún otro privilegio funciona.

| Rol | USAGE en `public` | CREATE en `public` |
|---|---|---|
| `rol_app_lectura` | ✓ | ✗ |
| `rol_app_escritura` | ✓ (heredado de `rol_app_lectura`) | ✗ |
| `rol_soporte` | ✓ | ✗ |
| `rol_reportes` | ✓ | ✗ |

**Justificación de `CREATE` denegado a todos:** ningún rol de aplicación debe
poder crear objetos en el esquema. `CREATE` queda reservado al superusuario o
al owner del esquema.

---

### 3.2 Tablas base

#### `categoria`

| Rol | S | I | U | D |
|---|---|---|---|---|
| `rol_app_lectura` | ✓ | ✗ | ✗ | ✗ |
| `rol_app_escritura` | ✓ (heredado) | ✗ | ✗ | ✗ |
| `rol_soporte` | ✓ | ✗ | ✗ | ✗ |
| `rol_reportes` | ✗ | ✗ | ✗ | ✗ |

**Justificación:** las categorías son datos de catálogo de solo lectura para la
aplicación. Ningún rol de aplicación modifica categorías; eso corresponde al owner.
`rol_reportes` accede a nombre de categoría a través de la vista materializada, no
directamente.

---

#### `producto`

| Rol | S | I | U (col) | D |
|---|---|---|---|---|
| `rol_app_lectura` | ✓ | ✗ | ✗ | ✗ |
| `rol_app_escritura` | ✓ (heredado) | ✗ | `UPDATE (stock)` | ✗ |
| `rol_soporte` | ✓ | ✗ | ✗ | ✗ |
| `rol_reportes` | ✗ | ✗ | ✗ | ✗ |

**Permiso por columna — `UPDATE (stock)` para `rol_app_escritura`:**
`sp_crear_pedido` ejecuta `UPDATE producto SET stock = stock - v_cantidad` dentro
del procedimiento. El procedimiento se ejecuta como `SECURITY DEFINER` o el llamador
necesita permiso directo sobre la columna. Ver conflicto §5.1 para la resolución.

**Justificación del UPDATE restringido a `stock`:** las columnas `precio`,
`nombre_producto`, `disponible` y `eliminado` no deben ser modificables por la
aplicación web. El permiso de columna las protege explícitamente.

---

#### `usuario`

| Rol | S (col) | I | U (col) | D |
|---|---|---|---|---|
| `rol_app_lectura` | ✗ | ✗ | ✗ | ✗ |
| `rol_app_escritura` | `SELECT (id_usuario, eliminado)` | ✗ | ✗ | ✗ |
| `rol_soporte` | `SELECT (id_usuario, nombre_usuario, apellido, mail, rol, eliminado, created_at)` | ✗ | ✗ | ✗ |
| `rol_reportes` | ✗ | ✗ | ✗ | ✗ |

**Justificación de acceso restringido por columna:**
- `contrasena` y `celular` son datos personales sensibles. Ningún rol de aplicación
  debe poder leerlos directamente.
- `rol_app_escritura` necesita `id_usuario` y `eliminado` únicamente para la
  validación interna de `sp_crear_pedido` (`IF NOT EXISTS (SELECT 1 FROM usuario
  WHERE id_usuario = p_id_usuario AND eliminado = FALSE)`).
- `rol_soporte` necesita poder consultar el estado del usuario para diagnóstico,
  pero no su contraseña ni teléfono.
- `rol_reportes` accede a nombre y apellido a través de `v_tp5_pedidos_usuario`,
  que no expone datos sensibles. No necesita acceso directo a la tabla.

**REVOKE explícito:**
```sql
REVOKE ALL ON usuario FROM PUBLIC;
REVOKE SELECT (contrasena) ON usuario FROM rol_soporte;
REVOKE SELECT (celular)    ON usuario FROM rol_soporte;
```
El `REVOKE FROM PUBLIC` inicial es la primera acción sobre esta tabla para
asegurarse de que ningún permiso por defecto quede activo. Luego los permisos
de columna se otorgan explícitamente.

---

#### `pedido`

| Rol | S | I | U (col) | D |
|---|---|---|---|---|
| `rol_app_lectura` | ✓ | ✗ | ✗ | ✗ |
| `rol_app_escritura` | ✓ (heredado) | ✓ | `UPDATE (estado, forma_pago, eliminado, total)` | ✗ |
| `rol_soporte` | ✓ | ✗ | ✗ | ✗ |
| `rol_reportes` | ✗ | ✗ | ✗ | ✗ |

**Justificación del INSERT para `rol_app_escritura`:**
`sp_crear_pedido` hace `INSERT INTO pedido (id_usuario, forma_pago)`. El INSERT
es parte del flujo transaccional del procedimiento.

**Justificación del UPDATE por columna:**
- `estado` se actualiza en HU-PED-03 (cambio de estado del pedido).
- `forma_pago` ídem.
- `eliminado` se necesita para el soft delete operativo del pedido.
- `total` — nota: `trg_total_ins` y `trg_total_upd` son `SECURITY INVOKER`. El
  trigger actualiza `pedido.total` ejecutándose con el rol del llamador. Por lo
  tanto `rol_app_escritura` necesita `UPDATE (total)` para que el trigger pueda
  escribir esa columna durante el `INSERT INTO detalle_pedido` que lo activa.
  Sin este permiso, el trigger fallará con "permission denied" aunque el INSERT
  en `detalle_pedido` esté permitido. Ver §5.2.
- `fecha`, `id_usuario` y `created_at` **no** se incluyen: nunca deben modificarse
  después de la inserción.

---

#### `detalle_pedido`

| Rol | S | I | U (col) | D |
|---|---|---|---|---|
| `rol_app_lectura` | ✓ | ✗ | ✗ | ✗ |
| `rol_app_escritura` | ✓ (heredado) | ✓ | `UPDATE (eliminado)` | ✗ |
| `rol_soporte` | ✓ | ✗ | ✗ | ✗ |
| `rol_reportes` | ✗ | ✗ | ✗ | ✗ |

**Justificación del INSERT para `rol_app_escritura`:**
`sp_crear_pedido` hace `INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad)`.

**Justificación del UPDATE restringido a `eliminado`:**
El soft delete de líneas de detalle (`queries.sql`, HU-PED-04) hace
`UPDATE detalle_pedido SET eliminado = TRUE WHERE id_pedido = ?`. Solo esa columna.
Las columnas `precio_unitario`, `subtotal` y `cantidad` son inmutables desde el
punto de vista del rol de aplicación: `fn_set_subtotal` es un trigger `BEFORE INSERT`
que asigna `NEW.precio_unitario` y `NEW.subtotal` directamente sobre la nueva fila
antes de que se escriba al disco. Esa asignación dentro del trigger no es una
sentencia `UPDATE` independiente y no requiere que el rol llamador tenga
`UPDATE (precio_unitario, subtotal)`. El permiso de `INSERT` sobre la tabla es
suficiente para que el trigger complete el INSERT con los valores calculados.

---

### 3.3 Vistas regulares (`Objects.sql` y `views_tp5.sql`)

Las vistas heredan permisos de las tablas base para su owner (que las puede
consultar), pero los roles de aplicación necesitan `SELECT` explícito sobre cada vista.

| Vista | `rol_app_lectura` | `rol_app_escritura` | `rol_soporte` | `rol_reportes` |
|---|---|---|---|---|
| `v_productos_vigentes` | ✓ SELECT | ✓ (heredado) | ✓ SELECT | ✗ |
| `v_pedidos_resumen` | ✓ SELECT | ✓ (heredado) | ✓ SELECT | ✗ |
| `v_pedido_detalle` | ✓ SELECT | ✓ (heredado) | ✓ SELECT | ✗ |
| `v_categorias_vigentes` | ✓ SELECT | ✓ (heredado) | ✓ SELECT | ✗ |
| `v_tp5_productos_categoria` | ✓ SELECT | ✓ (heredado) | ✓ SELECT | ✗ |
| `v_tp5_pedidos_usuario` | ✗ | ✗ | ✓ SELECT | ✗ |
| `v_tp5_detalle_pedido_productos` | ✓ SELECT | ✓ (heredado) | ✓ SELECT | ✗ |

**Justificación de `v_tp5_pedidos_usuario` restringida:**
Esta vista expone `mail` del usuario. No debe estar disponible para la lectura
genérica de la app ni para reportes externos. Solo `rol_soporte` la consulta para
diagnóstico operativo con identidad del cliente.

**Justificación de `rol_reportes` sin acceso a vistas regulares:**
`rol_reportes` está diseñado exclusivamente para dashboards analíticos que leen
desde la vista materializada. Las vistas regulares reflejan estado transaccional
en tiempo real y no son el instrumento de reporte; darles acceso ampliaría el
alcance más allá de lo necesario.

---

### 3.4 Vista materializada

| Vista | `rol_app_lectura` | `rol_app_escritura` | `rol_soporte` | `rol_reportes` |
|---|---|---|---|---|
| `mv_tp5_facturacion_categoria_mes` | ✗ | ✗ | ✓ SELECT | ✓ SELECT |

**Justificación:** la vista materializada es un artefacto de reporte analítico.
La app web no la consulta (usa las vistas regulares y las tablas base para datos
operativos). `rol_reportes` es su consumidor principal. `rol_soporte` puede usarla
para verificar el estado del último refresh sin necesidad de re-ejecutar la consulta
costosa.

**REFRESH y el privilegio MAINTAIN (PostgreSQL 17):**
En PostgreSQL 17 existe el privilegio `MAINTAIN` sobre tablas y vistas
materializadas. Un rol con `MAINTAIN` puede ejecutar `REFRESH MATERIALIZED VIEW`,
`REINDEX` y `CLUSTER` sobre ese objeto sin ser el owner ni superusuario.

**Decisión para este TP:** no se concede `MAINTAIN` a ningún rol de aplicación.
El refresh de `mv_tp5_facturacion_categoria_mes` queda reservado al owner del
objeto (el rol que ejecutó `CREATE MATERIALIZED VIEW`, típicamente el superusuario
de desarrollo o un rol administrativo dedicado). La razón es que no existe en la
consigna un requisito explícito de delegar el refresh, y concederlo sin necesidad
amplía el alcance más allá del mínimo. Si en el futuro se necesitara que
`admin_datos` ejecute el refresh, se añadiría:
`GRANT MAINTAIN ON mv_tp5_facturacion_categoria_mes TO admin_datos`
con justificación explícita en el informe.

---

### 3.5 Funciones y procedimiento

| Objeto | `rol_app_lectura` | `rol_app_escritura` | `rol_soporte` | `rol_reportes` |
|---|---|---|---|---|
| `calcular_total_pedido` | ✗ | ✓ EXECUTE | ✓ EXECUTE | ✗ |
| `fn_set_subtotal` | ✗ | ✗ | ✗ | ✗ |
| `fn_recalcular_total` | ✗ | ✗ | ✗ | ✗ |
| `fn_check_estado_transition` | ✗ | ✗ | ✗ | ✗ |
| `fn_check_categoria_baja_logica` | ✗ | ✗ | ✗ | ✗ |
| `sp_crear_pedido` | ✗ | ✓ EXECUTE | ✗ | ✗ |

**Justificación de funciones trigger sin permisos de aplicación:**
Las funciones de trigger (`fn_set_subtotal`, `fn_recalcular_total`,
`fn_check_estado_transition`, `fn_check_categoria_baja_logica`) son
`SECURITY INVOKER` por defecto, como toda función PL/pgSQL que no declara
explícitamente `SECURITY DEFINER`. Cuando el motor dispara un trigger, lo hace
en el contexto de la sentencia DML que lo activó: la función de trigger hereda
el rol del llamador original y verifica los permisos sobre las tablas que toca
contra ese rol. En la práctica esto es transparente porque las tablas afectadas
(`pedido`, `detalle_pedido`) ya tienen permisos concedidos al rol llamador
mediante la matriz de §3.2; el trigger no necesita permisos adicionales propios.
Los roles de aplicación nunca invocan estas funciones directamente; conceder
`EXECUTE` explícito sería ampliar el acceso sin propósito.

**Justificación de `calcular_total_pedido` para `rol_app_escritura` y `rol_soporte`:**
`fn_recalcular_total` invoca `calcular_total_pedido(id_pedido)` dentro de su
cuerpo. Como el trigger es `SECURITY INVOKER`, esa llamada se ejecuta con el
rol del llamador. Por lo tanto `rol_app_escritura` necesita `EXECUTE` sobre
`calcular_total_pedido` para que el trigger `trg_total_ins`/`trg_total_upd`
pueda completarse. `rol_soporte` también lo necesita para usar la función
directamente en diagnóstico (es `STABLE`, solo lectura).

**Justificación de `sp_crear_pedido` solo para `rol_app_escritura`:**
El procedimiento es el único punto de entrada válido para crear pedidos. La app web
(`app_web`) lo necesita. Ningún otro rol debe poder crear pedidos por este camino.

---

### 3.6 Membresías y roles LOGIN

```
rol_app_escritura  MEMBER OF  rol_app_lectura    (hereda todos sus permisos)

app_web            MEMBER OF  rol_app_escritura
admin_datos        MEMBER OF  rol_soporte
admin_datos        MEMBER OF  rol_reportes
```

**Justificación de la herencia `rol_app_escritura → rol_app_lectura`:**
La app web necesita leer catálogo, vistas y tablas para poder crear un pedido.
En lugar de duplicar permisos de SELECT, hereda el rol de lectura y agrega
solo los permisos de escritura.

**Justificación de `admin_datos` con doble membresía:**
El administrador de datos hace diagnóstico (soporte) y consulta reportes analíticos
(reportes), pero no crea pedidos ni modifica datos de negocio.

---

### 3.7 ALTER DEFAULT PRIVILEGES

`ALTER DEFAULT PRIVILEGES` define qué permisos se otorgan automáticamente a los
objetos creados en el futuro por el owner. Su uso indiscriminado puede exponer
tablas sensibles aún no existentes.

**Política adoptada: no otorgar SELECT sobre todas las tablas futuras.**
Un `ALTER DEFAULT PRIVILEGES … GRANT SELECT ON TABLES TO rol_app_lectura` haría
que cualquier tabla nueva (incluyendo una futura `auditoria_accesos` o
`datos_facturacion`) quedara disponible automáticamente para la app web. Esto viola
el principio de mínimo acceso.

En su lugar, los permisos sobre tablas se otorgan explícitamente objeto por objeto
al crear cada tabla. El único `ALTER DEFAULT PRIVILEGES` apropiado es para funciones
(ver abajo).

**Permisos de EXECUTE que PostgreSQL concede a PUBLIC sobre rutinas:**
PostgreSQL otorga `EXECUTE` a `PUBLIC` sobre todas las funciones y procedimientos
por defecto (`GRANT EXECUTE ON FUNCTION … TO PUBLIC` implícito al crear). Esto
significa que cualquier rol conectado puede llamar a `calcular_total_pedido` o a
`sp_crear_pedido` sin que se le haya concedido explícitamente.

Para revocar ese permiso por defecto en las rutinas existentes y en las futuras:

```sql
-- Rutinas existentes: revocar EXECUTE de PUBLIC en cada una
REVOKE EXECUTE ON FUNCTION calcular_total_pedido(BIGINT)    FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_set_subtotal()                FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_recalcular_total()            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_check_estado_transition()     FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION fn_check_categoria_baja_logica() FROM PUBLIC;

-- Rutinas futuras: evitar que las nuevas funciones creadas por el owner
-- reciban EXECUTE a PUBLIC por defecto.
-- Debe ejecutarse conectado como el owner que creará las rutinas futuras,
-- o usando FOR ROLE para indicar explícitamente ese owner:
ALTER DEFAULT PRIVILEGES FOR ROLE <owner_del_esquema>
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
```

`IN SCHEMA public` **no** es suficiente aquí: ese calificador filtra el ámbito
en que se aplica el privilegio, pero el permiso global de `EXECUTE` que PostgreSQL
da a `PUBLIC` al crear una función no es un privilegio de esquema — es un privilegio
de objeto. La cláusula `FOR ROLE` indica qué rol creador queda afectado por la
política, lo que sí bloquea el permiso implícito para todas las rutinas que ese
rol cree en el futuro. Reemplazar `<owner_del_esquema>` por el nombre real del
rol que ejecuta `CREATE FUNCTION` / `CREATE PROCEDURE` (ej: el superusuario de
desarrollo o un rol `owner_foodstore` dedicado).

**Qué no se incluye en DEFAULT PRIVILEGES para tablas:**
- No se otorgan SELECT, INSERT, UPDATE ni EXECUTE globales a ningún rol.
  Cada tabla nueva recibe permisos explícitos al momento de su creación.

---

## 4. REVOKE explícitos

### 4.1 Revocar PUBLIC por defecto en tabla sensible

```sql
REVOKE ALL ON usuario   FROM PUBLIC;
REVOKE ALL ON pedido    FROM PUBLIC;
REVOKE ALL ON detalle_pedido FROM PUBLIC;
```

PostgreSQL otorga implícitamente algunos permisos a `PUBLIC` en la base de datos.
Revocarlos explícitamente en las tablas de mayor sensibilidad asegura que un rol
nuevo o mal configurado no herede acceso accidental.

### 4.2 Revocar columnas sensibles de `usuario`

```sql
REVOKE SELECT (contrasena) ON usuario FROM PUBLIC;
REVOKE SELECT (celular)    ON usuario FROM PUBLIC;
```

El permiso de columna en PostgreSQL es aditivo: si se otorga `SELECT` sobre la
tabla y luego se revoca una columna, el revoke a nivel de columna **no surte efecto**
sobre permisos ya otorgados a nivel de tabla. Por eso el flujo correcto es:

1. `REVOKE ALL ON usuario FROM PUBLIC` (base).
2. Otorgar solo las columnas necesarias con `GRANT SELECT (col1, col2) ON usuario TO rol`.
3. No otorgar nunca `GRANT SELECT ON usuario TO <cualquier_rol>` (sin restricción de columna).

---

## 5. Conflictos identificados y propuestas de resolución

### 5.1 Conflicto: `sp_crear_pedido` con SECURITY INVOKER — permisos directos permiten omitir el procedimiento

**Flujo completo de `sp_crear_pedido` con SECURITY INVOKER y permisos requeridos:**

`sp_crear_pedido` es `SECURITY INVOKER` por defecto. El motor comprueba los
permisos del rol llamador (`rol_app_escritura` / `app_web`) en cada paso:

| Paso dentro del procedimiento | Operación | Permiso requerido en `rol_app_escritura` |
|---|---|---|
| Validar usuario | `SELECT id_usuario, eliminado FROM usuario` | `SELECT (id_usuario, eliminado)` sobre `usuario` |
| Crear pedido | `INSERT INTO pedido (id_usuario, forma_pago)` | `INSERT` sobre `pedido` |
| Bloquear stock | `SELECT stock, disponible FROM producto FOR UPDATE` | `SELECT` sobre `producto` |
| Insertar detalle | `INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad)` | `INSERT` sobre `detalle_pedido` |
| Trigger `fn_set_subtotal` (INVOKER) | `SELECT precio FROM producto` | `SELECT` sobre `producto` (ya cubierto) |
| Trigger `fn_set_subtotal` | Asigna `NEW.precio_unitario` y `NEW.subtotal` en la nueva fila | Ninguno adicional — es parte del INSERT, no una sentencia UPDATE separada |
| Trigger `fn_recalcular_total` (INVOKER) | `calcular_total_pedido(id_pedido)` | `EXECUTE` sobre `calcular_total_pedido` |
| Trigger `fn_recalcular_total` | `UPDATE pedido SET total = …` | `UPDATE (total)` sobre `pedido` |
| Descontar stock | `UPDATE producto SET stock = stock - v_cantidad` | `UPDATE (stock)` sobre `producto` |

**Consecuencia directa de SECURITY INVOKER:**
Con estos permisos directos sobre tablas, `app_web` puede — técnicamente — ejecutar
`INSERT INTO pedido`, `UPDATE producto SET stock`, e `INSERT INTO detalle_pedido`
sin pasar por `sp_crear_pedido`. El procedimiento no es la única vía posible;
es la vía correcta por convención de negocio, pero no está enforceada a nivel de
permisos. Esto debe declararse explícitamente en el informe.

**Opción A — SECURITY INVOKER (actual, para este TP):**
- Permisos directos sobre tablas según la tabla de arriba.
- Ventaja: transparente, auditable, sin riesgo de escalada de privilegios.
- Limitación: no enforcea el uso del procedimiento; un bug de aplicación podría
  hacer un INSERT directo en `pedido` sin validaciones.

**Opción B — SECURITY DEFINER con propietario no superusuario:**
El procedimiento se re-crea con `SECURITY DEFINER` y un owner que sea un rol
dedicado (ej: `owner_sp_pedido`) con los permisos mínimos necesarios, sin ser
superusuario:
- `owner_sp_pedido` tiene los permisos de la tabla de arriba.
- Se añade `SET search_path = public, pg_temp` en la definición para evitar
  ataques de búsqueda en esquema.
- `rol_app_escritura` solo necesita `EXECUTE` sobre el procedimiento; pierde
  todos los permisos directos sobre tablas de escritura.
- Ventaja: enforcea el uso del procedimiento; reduce drásticamente la superficie
  de ataque del rol de aplicación.
- Riesgo: si el procedimiento tiene un bug, se ejecuta con permisos de `owner_sp_pedido`
  (no del superusuario, a diferencia de un DEFINER con superusuario).
- Requiere modificar `Objects.sql` para añadir `SECURITY DEFINER` y el `search_path`.

> **Decisión pendiente de validación manual:** confirmar con la cátedra cuál opción
> se exige antes de escribir `roles.sql`. La Opción A es más sencilla de implementar
> y verificar; la Opción B es más segura para producción.

---

### 5.2 Nota: `fn_recalcular_total` requiere `EXECUTE` sobre `calcular_total_pedido` y `UPDATE (total)` sobre `pedido`

`fn_recalcular_total` es `SECURITY INVOKER` y emite dos operaciones bajo el rol
del llamador:

1. Llama a `calcular_total_pedido(id_pedido)` — requiere `EXECUTE` sobre esa función.
2. Ejecuta `UPDATE pedido SET total = …` — requiere `UPDATE (total)` sobre `pedido`.

Ambos permisos están ya reflejados en las matrices definitivas de §3.2 (`pedido`)
y §3.5 (`calcular_total_pedido` con ✓ para `rol_app_escritura`). No se necesita
ninguna otra corrección de permisos para que el flujo completo funcione.

**Con la Opción B (SECURITY DEFINER, §5.1):** todos estos permisos sobre columnas
y sobre `calcular_total_pedido` desaparecen del rol de aplicación, porque el trigger
se ejecutaría con los permisos del `owner_sp_pedido`. Es un argumento adicional a
favor de esa opción para producción.

---

## 6. Plan de verificación

### 6.1 Verificar roles creados y membresías

**En psql:**
```sql
\du
```

**Equivalente SQL para DBeaver** (`\du` no funciona en DBeaver):
```sql
SELECT r.rolname,
       r.rolcanlogin,
       r.rolsuper,
       ARRAY(
           SELECT b.rolname
           FROM   pg_catalog.pg_auth_members m
           JOIN   pg_catalog.pg_roles b ON b.oid = m.roleid
           WHERE  m.member = r.oid
       ) AS member_of
FROM   pg_catalog.pg_roles r
WHERE  r.rolname NOT LIKE 'pg_%'
ORDER  BY r.rolname;
```

---

### 6.2 Verificar permisos sobre tablas

```sql
SELECT grantee,
       table_name,
       privilege_type,
       is_grantable
FROM   information_schema.role_table_grants
WHERE  table_schema = 'public'
  AND  grantee IN (
      'rol_app_lectura','rol_app_escritura',
      'rol_soporte','rol_reportes',
      'app_web','admin_datos'
  )
ORDER  BY table_name, grantee, privilege_type;
```

---

### 6.3 Verificar permisos por columna

```sql
SELECT grantee,
       table_name,
       column_name,
       privilege_type
FROM   information_schema.column_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'usuario'
ORDER  BY grantee, column_name;
```

Verificar que `contrasena` y `celular` no aparecen para ningún rol de aplicación.

---

### 6.4 Verificar permisos sobre rutinas (incluye PUBLIC)

```sql
SELECT grantee,
       routine_name,
       privilege_type
FROM   information_schema.routine_privileges
WHERE  routine_schema = 'public'
ORDER  BY routine_name, grantee;
```

`sp_crear_pedido` debe aparecer con `EXECUTE` para `rol_app_escritura` **y no
para `PUBLIC`**. Las funciones de trigger no deben aparecer para ningún rol de
aplicación. Si `PUBLIC` aparece como grantee de alguna rutina, el REVOKE de §3.7
no se aplicó correctamente.

---

### 6.5 Prueba efectiva de permisos — `app_web`

Conectarse como `app_web` en DBeaver (nueva conexión con ese usuario) y ejecutar:

```sql
-- Debe funcionar (SELECT sobre vista):
SELECT * FROM v_productos_vigentes LIMIT 5;

-- Debe funcionar (EXECUTE sobre procedimiento):
CALL sp_crear_pedido(2, 'EFECTIVO', '[{"producto_id": 1, "cantidad": 1}]'::jsonb);

-- Debe fallar con "permission denied":
SELECT contrasena FROM usuario WHERE id_usuario = 1;

-- Debe fallar con "permission denied":
DELETE FROM pedido WHERE id_pedido = 1;

-- Debe fallar con "permission denied":
SELECT * FROM mv_tp5_facturacion_categoria_mes;
```

---

### 6.6 Prueba efectiva de permisos — `admin_datos`

```sql
-- Debe funcionar (SELECT sobre vista materializada):
SELECT * FROM mv_tp5_facturacion_categoria_mes ORDER BY mes, facturado DESC;

-- Debe funcionar (soporte — vista operativa):
SELECT * FROM v_tp5_pedidos_usuario WHERE id_usuario = 2;

-- Debe fallar con "permission denied":
CALL sp_crear_pedido(2, 'EFECTIVO', '[{"producto_id": 1, "cantidad": 1}]'::jsonb);

-- Debe fallar con "permission denied":
SELECT contrasena FROM usuario WHERE id_usuario = 1;

-- Debe fallar con "permission denied":
INSERT INTO categoria (nombre_categoria) VALUES ('Test');
```

---

### 6.7 Prueba de REVOKE efectivo sobre `PUBLIC`

```sql
-- Conectarse como un rol nuevo sin membresías explícitas y verificar:
SELECT * FROM usuario;
-- Debe fallar: "permission denied for table usuario"
```

---

## 7. Resumen de la política de mínimo acceso aplicada

| Principio | Aplicación concreta |
|---|---|
| Mínimo privilegio | Ningún rol de aplicación tiene `SUPERUSER`, `CREATEDB` ni `CREATEROLE` |
| Sin permisos directos en `PUBLIC` | `REVOKE ALL ON usuario FROM PUBLIC` como primera acción; `REVOKE EXECUTE ON FUNCTION … FROM PUBLIC` sobre todas las rutinas |
| Columnas sensibles protegidas | `contrasena` y `celular` no aparecen en ningún `GRANT` |
| SECURITY INVOKER permite INSERT/UPDATE directo | Con Opción A, `rol_app_escritura` tiene permisos directos sobre tablas; el procedimiento es la vía correcta por convención, no la única técnicamente posible. Esto se declara explícitamente como limitación de la opción |
| Triggers INVOKER amplían permisos requeridos | `fn_recalcular_total` exige `UPDATE (total)` sobre `pedido` y `EXECUTE` sobre `calcular_total_pedido` para el rol llamador; `fn_set_subtotal` asigna columnas en `NEW` y **no** requiere `UPDATE` adicional |
| Sin DEFAULT PRIVILEGES sobre todas las tablas | Tablas futuras reciben permisos explícitos; `ALTER DEFAULT PRIVILEGES FOR ROLE <owner> REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` bloquea el EXECUTE implícito en rutinas futuras |
| MAINTAIN no concedido | Refresh de la vista materializada queda reservado al owner; sin requisito explícito de la consigna no se delega |
| `\du` equivalente en DBeaver | Consulta sobre `pg_catalog.pg_roles` y `pg_auth_members` documentada en §6.1 |
