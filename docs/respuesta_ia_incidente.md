# Reconstrucción del log — sesión 29720, `postgres@foodstore_tp_u5`, 2026-10-15

## 1. Hechos observables (cronología)

| Hora | Evento |
|---|---|
| 12:05:20.846 | Se ejecuta `SET LOCAL ROLE app_web` dentro de la sesión (session_user sigue siendo `postgres`). |
| 12:05:20.847 | Se consulta `current_user` / `session_user` para verificar el cambio de rol. Resultados no registrados. |
| 12:05:26.819 | `fn_autenticar(CORREO_A, CLAVE_A)` → **FALLO** (~40 ms). |
| 12:05:30.940 | `fn_autenticar(CORREO_A, CLAVE_B)` → **FALLO** (~8 ms). |
| 12:05:34.688 | `fn_autenticar(CORREO_B, CLAVE_C)` → **FALLO** (~3 ms). |
| 12:05:39.888 | `fn_autenticar(CORREO_A, CLAVE_D)` → **OK** (~7 ms). |
| 12:06:18.394 | `SELECT id_usuario, eliminado FROM public.usuario` — se ejecuta **bajo `app_web`** y no fue denegada, luego `app_web` tiene SELECT sobre la tabla completa. |
| 12:07:12.474 | `SAVEPOINT sp_intento_grant` seguido inmediatamente de `GRANT admin_datos TO app_web` → **ERROR**: permiso denegado (solo roles con ADMIN OPTION pueden otorgar `admin_datos`). |
| 12:08:06.139 | `ROLLBACK TO SAVEPOINT sp_intento_grant` (~54 s después del error). |
| 12:08:19.162 | `ROLLBACK` final de la transacción (~13 s después). |

Observaciones factuales adicionales: la sesión estuvo en **una única transacción** de principio a fin (`SET LOCAL ROLE` es local a transacción y el `ROLLBACK` final lo confirma); `fn_autenticar` emite sus propios logs de resultado; los intervalos entre intentos de autenticación fueron de ~4–5 s, regulares.

## 2. Inferencias (no demostrables con el log)

- **El patrón 3 fallos + 1 éxito sobre CORREO_A** es compatible con dos lecturas opuestas: usuario legítimo que olvidó la contraseña y la recordó, o ataque de fuerza bruta/diccionario que acertó al cuarto intento. El log no permite distinguirlas.
- **CORREO_B** pudo ser un cambio de cuenta, un typo, o un intento de sondeo sobre otra identidad.
- El `GRANT` dentro de un savepoint sugiere **conocimiento anticipado del fallo** (script defensivo o consigna de clase — el nombre de la base `foodstore_tp_u5` sugiere ejercicio académico). También podría ser escalada de privilegios real abortada.
- La pausa de 54 s entre el error y el rollback es consistente con lectura de un mensaje de error o de consignas, pero es indistinguible de duda humana o de automatización pausada.
- `postgres` como session_user sugiere entorno de desarrollo/aula; no prueba quién estaba frente al teclado.

## 3. Qué no puede demostrarse con el log

- **Quién** ejecutó cada sentencia (no hay mapeo actor↔sesión; todo corre como `postgres`).
- Si la contraseña acertada fue recordada, adivinada, filtrada o provista por terceros.
- Si el `GRANT` era malicioso o pedagógico.
- Qué devolvió el `SELECT` sobre `usuario` (el log no incluye resultados).
- El conjunto completo de privilegios de `app_web` y `admin_datos`, ni si hay otros roles con ADMIN OPTION.
- Si hubo bloqueo de cuenta o rate limiting en `fn_autenticar` que simplemente no se activó en 4 intentos.
- Qué ocurrió fuera del extracto (otras sesiones,前后 eventos, persistencia posterior).

## 4. Riesgos detectados

1. **Fuerza bruta sin freno visible**: 4 intentos en ~13 s sin lockout registrado. Si `fn_autenticar` no implementa contador/ventana temporal, una máquina agota diccionarios contra cualquier correo.
2. **Intento de escalada de privilegios**: `GRANT admin_datos TO app_web`. Hoy falla por falta de ADMIN OPTION, pero el intento queda registrado; si algún día un rol intermedio recibe ADMIN OPTION por error, el ataque escala.
3. **Superuser como sesión de aplicación**: `postgres` + `SET LOCAL ROLE` es una frontera blanda — `postgres` siempre puede volver a cambiar de rol. Un error o una sentencia inyectada corre como superuser.
4. **Enumeración de usuarios**: `app_web` puede listar `id_usuario` y `eliminado` de toda la tabla, incluidos usuarios soft-deleteados.
5. **Credenciales en texto plano en el SQL ejecutado**: `fn_autenticar('<CORREO>','<CLAVE>')` significa que con `log_statement = all` las contraseñas reales aterrizan en los logs (el extracto las anonimiza, pero la práctica es el riesgo).
6. **Falta de atribución**: sin rol de login dedicado por actor, ninguna acción es auditable individualmente.

## 5. Medidas de contención propuestas

**Inmediatas (hoy):**
- Auditar `pg_auth_members` y `pg_roles` para confirmar que nadie tiene ADMIN OPTION sobre `admin_datos` y que `admin_datos` es NOLOGIN.
- Revisar la definición de `fn_autenticar`: agregar contador de intentos fallidos por correo con ventana temporal y bloqueo (o integrar `auth_delay` / `pg_fail2ban` a nivel servidor).
- Cambiar la práctica de invocar la función con literales: usar parámetros tipados y, preferentemente, recibir solo el hash (hashear en el cliente o usar `crypt`/`pgcrypto` con sal en servidor, nunca la clave en claro en el texto SQL).
- Poner `log_statement = none|ddl` en producción y/o `log_parameter_max_length` limitado, para que las claves no se filtren al log.
- Verificar el GRANT efectivo de `app_web` sobre `usuario`; si la app solo necesita el usuario actual, sustituir por una vista con `WHERE id = current_setting('app.user_id')::int AND eliminado = FALSE`.

**Mediano plazo:**
- Conectar la aplicación con un rol `NOLOGIN` de aplicación que haga `SET ROLE app_web`, nunca como `postgres`.
- Habilitar **pgAudit** con `audit = 'write, role, privilege'` para tener trazabilidad real por rol.
- Definir política de rate limiting y alerta: >N fallos de autenticación por correo o por IP en ventana de M minutos genera alerta.

**Sobre este incidente concreto:** dado el contexto de ejercicio (`foodstore_tp_u5`), lo más probable es una prueba pedagógica de roles — pero el log **no lo prueba**, y todas las debilidades anteriores son reales independientemente de la intención. Conviene tratarlo como ejercicio y, aun así, aplicar los puntos de la primera lista.

¿Querés que arme un plan de implementación para alguno de estos puntos (por ejemplo, el rate limiting en `fn_autenticar` o la restricción de la tabla `usuario`)?
