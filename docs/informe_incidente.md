# Simulacro de incidente y análisis del log — Unidad 5

## Alcance y ejecución

El ejercicio se realizó exclusivamente en la copia `foodstore_tp_u5`. Se usó una conexión de DBeaver autenticada como `postgres` y `SET LOCAL ROLE app_web` para simular los permisos de la aplicación; **no fue un inicio de sesión real como `app_web`**. Se creó un usuario sintético dentro de una transacción y se cerró todo con `ROLLBACK`.

La secuencia observada fue: tres llamadas fallidas a `fn_autenticar`, una llamada exitosa que devolvió el ID sintético **40010**, una lectura sin `LIMIT` de las columnas `id_usuario` y `eliminado` de `usuario`, y un intento fallido de `GRANT admin_datos TO app_web`. El error indicó que faltaba la opción `ADMIN` sobre `admin_datos`. Después se ejecutaron `ROLLBACK TO SAVEPOINT` y `ROLLBACK`.

Las verificaciones posteriores en DBeaver dieron **0** usuarios sintéticos restantes y **0** membresías nuevas de `app_web` en `admin_datos`. El prefijo global del log se restauró a `%t `. Estos resultados proceden de las consultas de prueba; el log, por sí solo, no muestra las filas devueltas ni prueba la persistencia final de los cambios.

## Evidencia y respuesta de IA

El extracto [log_simulacro_anonimizado.txt](log_simulacro_anonimizado.txt) conserva fecha, PID, sentencias y resultados de `fn_autenticar`, pero sustituye los correos y las claves por marcadores. Fue el material preparado para el análisis sin contexto adicional en OpenCode. La [respuesta íntegra](respuesta_ia_incidente.md) se conserva sin corregirla para poder evaluar sus aciertos y errores.

OpenCode reconstruyó correctamente el orden principal de los eventos y distinguió que el motivo del intento de `GRANT` no puede deducirse solo del log. También reconoció que el `SELECT` registrado no permite saber qué filas devolvió.

## Comparación crítica

| Afirmación de OpenCode | Evaluación humana |
|---|---|
| El `SELECT` demuestra acceso a “la tabla completa”. | **Incorrecto.** La consulta solo lee `id_usuario` y `eliminado`. `roles.sql` concede a `app_web` lectura de esas columnas, no de `usuario.contrasena` ni de todas las columnas. Tampoco se puede obtener el número de filas desde este log. |
| `admin_datos` debería comprobarse como `NOLOGIN`. | **No corresponde a este diseño.** `roles.sql` lo crea expresamente como `LOGIN PASSWORD NULL`; el control relevante aquí era que `app_web` no pudiera recibir su membresía. |
| Los intervalos entre la sentencia y `RAISE LOG` son tiempos de ejecución de la función. | **No demostrado.** Son diferencias entre marcas de eventos del log, no mediciones completas de duración de la consulta. |
| La conexión de `postgres` representa una aplicación que opera como superusuario. | **Inferencia errónea para este caso.** Fue una conexión administrativa usada para el simulacro; `SET LOCAL ROLE` permitió probar permisos de `app_web`. No hay evidencia de que una aplicación real se conecte como `postgres`. |
| Conviene conectar con un rol `NOLOGIN` que haga `SET ROLE app_web`. | **Inviable tal como está escrito:** un rol `NOLOGIN` no puede iniciar la conexión. En el proyecto, `app_web` ya es `LOGIN` y hereda roles de grupo `NOLOGIN`. |
| Una vista filtrada por `current_setting('app.user_id')` resolvería el acceso por usuario. | **No se acepta como control de seguridad sin más diseño:** si el propio rol puede fijar libremente esa variable, también podría cambiar el identificador consultado. |
| Habilitar pgAudit con `audit = 'write, role, privilege'`. | **No se acepta literalmente:** el parámetro es `pgaudit.log` y las clases incluyen `READ`, `WRITE` y `ROLE`, no `privilege` como clase separada. Requeriría instalación y configuración adicionales. |
| Las sentencias de autenticación pueden exponer claves en el log. | **Advertencia válida.** En este simulacro solo se usaron claves ficticias. El log bruto no se publica; el extracto se anonimiza. Pasar parámetros no elimina por sí solo el riesgo si se registran los valores de enlace. |
| Limitar `log_parameter_max_length` o enviar un hash desde el cliente resolvería la exposición. | **No se adopta como solución suficiente.** El límite de parámetros no borra contraseñas escritas como literales dentro del SQL, como en esta prueba. Un hash enviado por el cliente también podría convertirse en una credencial reutilizable. Se requiere un diseño de autenticación y registro específico. |

La hipótesis de fuerza bruta es razonable para un analista que solo ve el log, pero **no describe lo que ocurrió**: los cuatro intentos fueron pasos deliberados de una prueba controlada. El log permite ver el patrón, no la intención. La ausencia de limitación de intentos en la función es un tema de mejora futura, no evidencia de un ataque real en esta ejecución.

## Decisión humana

Se clasifica como **simulacro contenido, no como incidente real**. No se observaron credenciales reales comprometidas ni escalamiento de privilegios; el `GRANT` fue rechazado y el `ROLLBACK` dejó sin efecto el usuario sintético. No corresponde bloquear cuentas ni aplicar cambios de emergencia por esta prueba.

Sí quedan oportunidades de mejora separadas del incidente: revisar la necesidad de permitir enumerar `id_usuario` y `eliminado`, diseñar límites de intentos de autenticación y evitar el registro de credenciales en entornos reales. Cualquier cambio de permisos o de auditoría deberá probarse aparte; no se aplicó como consecuencia automática de la respuesta de IA.
