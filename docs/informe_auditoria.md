# Informe — TP Unidad 5, Parte B: Auditoría mediante logs — Food Store

> Prueba realizada en DBeaver sobre `foodstore_tp_u5` (PostgreSQL 17).
> La evidencia citada es un **resumen normalizado y anonimizado** de los
> eventos observados (`docs/log_auditoria_prueba.txt`), **no una
> transcripción literal** del log; el log bruto no se incluye en el
> repositorio.

---

## 1. Objetivo y alcance

Verificar el uso del registro de logs del servidor como mecanismo de
auditoría: qué actividad deja rastro, qué no, y con qué límites. La prueba
cubre tres casos: (a) DML temporal de categoría, (b) lectura puntual del
catálogo y (c) un intento de conexión fallido. La comprobación de que no
quedaron datos se hace **fuera** del log.

---

## 2. Entorno y configuración de la prueba

| Parámetro | Valor durante la prueba | Valor final restaurado |
|---|---|---|
| `log_connections` | `on` | `off` |
| `log_disconnections` | `on` | `off` |
| `log_statement` | `mod` | `none` |
| `log_line_prefix` | `%m [%p] %u@%d %r ` | `%t ` |

- **Motor / base:** PostgreSQL 17 sobre `foodstore_tp_u5`.
- **Zona horaria de los eventos:** `-03`.
- **Archivo de log del collector:** `postgresql-2026-10-14_054750.log`
  (en el `log_directory` del servidor; la ruta local se omite).
- **PID de la sesión de pruebas SQL:** `33484`.
- Para el caso de lectura se usó `SET LOCAL log_statement = 'all'` dentro de
  una transacción, que después se revirtió: `all` nunca quedó activo.

La configuración de logging se **activó** con `ALTER SYSTEM SET` y
`ALTER DATABASE ... SET`, y se **revirtió** al terminar con
`ALTER SYSTEM RESET`, `ALTER DATABASE ... RESET` y una recarga de
configuración (ver §7). No quedó configuración alterada.

---

## 3. Qué quedó registrado

Registros observados en el archivo del collector (resumen normalizado):

| Quién | Qué | Cuándo (14/10/2026, -03) | Origen |
|---|---|---|---|
| `postgres` (PID `33484`) | `INSERT` de `categoria` (`TP_U5_AUD_categoria_tmp`) | 23:23:47.122 | sesión local de la prueba |
| `postgres` (PID `33484`) | `UPDATE` de esa misma categoría | 23:23:52.978 | sesión local de la prueba |
| `postgres` (PID `33484`) | `SELECT` controlado del catálogo | 23:24:18.016 | sesión local de la prueba |
| `postgres` (PID `33484`) | `ROLLBACK` (cierre de la transacción del `SELECT` con `SET LOCAL`) | 23:24:29.317 | sesión local de la prueba |
| Rol `app_web` | `FATAL: password authentication failed` | 23:36:52.694 | host `[IP omitida]`, puerto `[puerto omitido]` |

- Bajo `log_statement = mod`, el `INSERT` y el `UPDATE` se registran porque
  son sentencias que modifican datos. Como DBeaver usa el protocolo
  extendido, en el log esas operaciones aparecen como `ejecutar <unnamed>`
  (no como `statement:`).
- Hubo una pareja previa de `INSERT`/`UPDATE`: la prueba se repitió. No se
  documenta aquí la causa de la repetición.
- El `SELECT` no se registra bajo `mod`; quedó capturado solo porque se
  elevó el nivel con `SET LOCAL log_statement = 'all'` en una transacción,
  que se revirtió (no dejó `all` activo).
- El evento de conexión fallida aparece como `FATAL` con el rol `app_web`.

---

## 4. Qué NO quedó registrado (y por qué)

- **SELECT ordinarios:** con `log_statement = mod` no se registran. El
  `SELECT` de identificación del entorno (bloque de lectura) no aparece en
  el log. Para capturar una lectura hubo que subir el nivel de forma
  temporal (`SET LOCAL log_statement = 'all'`), que es justamente lo que se
  hizo para el `SELECT` controlado.
- **Clasificación de `SET` y control transaccional:** `SET` no es DDL ni
  DML, por lo que bajo `mod` no necesariamente aparece; el `SELECT`
  posterior sí queda registrado porque en ese momento rige `all`.

---

## 5. Qué NO prueba el log (limitaciones)

- **Una línea de sentencia no demuestra que el cambio haya quedado
  confirmado.** El `INSERT` y el `UPDATE` del caso (a) quedaron registrados,
  pero el log muestra el **intento** y el texto ejecutado, no el efecto final
  sobre los datos. El `ROLLBACK` registrado a las 23:24:29 corresponde al
  bloque del `SELECT` con `SET LOCAL`, **no** a la reversión del
  `INSERT`/`UPDATE`; esa no-persistencia se acredita con el conteo = 0 (§6).
- **La persistencia se verificó aparte**, con una consulta de conteo
  posterior (§6), no con el log.
- **Puede contener datos sensibles.** Bajo `log_statement`, PostgreSQL puede
  incluir los **valores de los parámetros** del protocolo extendido
  (`log_parameter_max_length` por defecto `-1` los registra completos), y el
  texto de las sentencias puede revelar datos personales e incluso
  credenciales. Esto obliga a tratar el log como evidencia sensible.
- **Alcance de servidor:** el archivo es compartido por todas las sesiones y
  bases de la instancia; no está separado por aplicación ni por usuario. El
  PID permite correlacionar líneas de una misma sesión.
- **Marcas de tiempo** en la zona horaria del servidor (`-03`).
- **Integridad relativa:** el archivo vive en el sistema operativo; su valor
  como evidencia depende de la protección del host y de la política de
  retención. No es, por sí solo, prueba de cumplimiento.

---

## 6. Verificación de persistencia (fuera del log)

Se ejecutó, en otro momento posterior:

```sql
SELECT count(*) FROM categoria WHERE nombre_categoria LIKE 'TP_U5_AUD_%';
```

Resultado: **conteo = 0** (la consulta devolvió una fila con valor `0`). La
categoría temporal `TP_U5_AUD_categoria_tmp` no persistió; la operación quedó
registrada en el log como intento, pero sin efecto en la base.

---

## 7. Restauración de configuración

Al finalizar la prueba se revirtió la configuración temporal a los valores
originales:

| Parámetro | Valor final |
|---|---|
| `log_connections` | `off` |
| `log_disconnections` | `off` |
| `log_statement` | `none` |
| `log_line_prefix` | `%t ` |

La activación se hizo con `ALTER SYSTEM SET` y `ALTER DATABASE foodstore_tp_u5 SET`;
la restauración se hizo con `ALTER SYSTEM RESET`, `ALTER DATABASE foodstore_tp_u5 RESET`
y una recarga de configuración. No quedó configuración alterada. El `SET LOCAL`
usado para la lectura se revirtió con el `ROLLBACK` de su propia transacción.

---

## 8. Anonimización y manejo de la evidencia

- `docs/log_auditoria_prueba.txt` es un **resumen normalizado**, no una
  transcripción literal del log. Se omitieron IP, puertos, rutas locales y
  datos personales.
- No se incluyen contraseñas. El intento fallido de `app_web` usó una
  contraseña **ficticia** (no real), que no se comparte ni se registra en
  este repositorio; el rol tenía `PASSWORD NULL`, por lo que la
  autenticación por contraseña falló.
- **Antes de compartir o subir cualquier log bruto**, revisarlo y
  anonimizarlo: puede contener usuarios, hosts, correos, nombres y valores
  de parámetros. Recortar solo las líneas del caso (el PID `33484` ayuda a
  aislarlas en la sesión SQL; el evento `FATAL` de `app_web` se identifica
  por su fecha/hora).

---

## 9. Conclusión

- `log_statement = mod` registra las modificaciones (`INSERT`/`UPDATE`) pero
  **no** las lecturas ordinarias; para auditar un `SELECT` hay que elevar el
  nivel de forma temporal.
- El log prueba **qué sentencia se envió y cuándo**, no que el cambio se
  haya confirmado: el `INSERT`/`UPDATE` quedó registrado, pero la
  no-persistencia se comprobó aparte (conteo = 0).
- Un login fallido deja rastro como `FATAL` con el rol afectado y el origen
  (anonimizable), sin exponer la contraseña usada (ficticia) en la prueba.
- La configuración temporal se activó con `ALTER SYSTEM SET` /
  `ALTER DATABASE ... SET` y se restauró por completo con
  `ALTER SYSTEM RESET` / `ALTER DATABASE ... RESET` y recarga.

---

**Entregables (repo):** `sql/auditoria_test.sql`, `docs/log_auditoria_prueba.txt`,
`docs/informe_auditoria.md`.
