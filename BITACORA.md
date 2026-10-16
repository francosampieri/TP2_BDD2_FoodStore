# Bitácora de uso de IA — Trabajo práctico Unidad 5

Esta bitácora resume los prompts relevantes de las Partes A a D, la respuesta obtenida y la comprobación humana. Cuando no se conservó el texto literal del prompt, se registra su **contenido resumido**, sin presentarlo como una transcripción. Las mediciones y resultados citados proceden de ejecuciones manuales en DBeaver sobre `foodstore_tp_u5`.

## Parte A — Roles y permisos

| Herramienta y prompt relevante | Respuesta o artefacto | Validación y decisión humana |
|---|---|---|
| Kiro: especificar una matriz de mínimos privilegios para lectura, escritura, soporte y reportes, con protección de `usuario.contrasena` y sin permisos `DELETE`. | `docs/kiro_roles_spec/spec_roles_tp_u5.md`. Propuso roles de grupo y los logins `app_web` y `admin_datos`. | Se corrigieron explicaciones iniciales sobre funciones trigger `SECURITY INVOKER`, permisos necesarios para `sp_crear_pedido` y privilegios por defecto. Se decidió no conceder `MAINTAIN` a los roles de aplicación. |
| OpenCode: implementar los roles y privilegios de la especificación en `sql/roles.sql`, con verificaciones de acceso. | Script de creación y GRANT/REVOKE. | Se ejecutó en la copia de trabajo. Las nueve comprobaciones de privilegios dieron lo esperado: seis controles para `app_web` y tres para `admin_datos`. Una prueba de pedido con `app_web` redujo el stock de 17 a 16; el `ROLLBACK` lo devolvió a 17. Se aceptó el diseño verificado, sin afirmar que `app_web` solo puede escribir mediante el procedimiento: con `SECURITY INVOKER` también posee los permisos directos necesarios. |

## Parte B — Auditoría

| Herramienta y prompt relevante | Respuesta o artefacto | Validación y decisión humana |
|---|---|---|
| OpenCode: preparar una prueba de auditoría con modificación temporal, lectura controlada, conexión fallida y restauración de logging. | `sql/auditoria_test.sql`. | Se ejecutó en DBeaver. El log registró `INSERT`, `UPDATE`, un `SELECT` bajo `log_statement = all` y un intento fallido de conexión. Un conteo posterior dio 0 categorías temporales. Se confirmó que el `ROLLBACK` visible del bloque de lectura **no** demostraba por sí mismo la reversión del `INSERT`/`UPDATE`. |
| OpenCode: redactar el extracto anonimizado y el informe de auditoría sin presentar un resumen como copia literal del log. | `docs/log_auditoria_prueba.txt` y `docs/informe_auditoria.md`. | Se corrigieron horarios, PID, el significado del `ROLLBACK` y la descripción de la restauración con `ALTER SYSTEM`/`ALTER DATABASE`. Se verificó que `log_connections`, `log_disconnections` y `log_statement` volvieron a sus valores iniciales y el prefijo a `%t `. |

## Parte C — Simulacro y reconstrucción de un incidente

| Herramienta y prompt relevante | Respuesta o artefacto | Validación y decisión humana |
|---|---|---|
| OpenCode: reconstruir `fn_autenticar` y `fn_resetear_password` con `pgcrypto`, sin autenticar contraseñas antiguas en texto plano, y preparar un simulacro reversible con usuario sintético. | `sql/autenticacion_u5.sql` y `sql/simulacro_incidente.sql`. | Antes de ejecutar, se corrigió la dependencia del orden de evaluación de `AND`, se separaron propietarios y privilegios de autenticación y reseteo, y se agrupó creación/revocación de rutinas en una transacción. Otra propuesta, `SET LOCAL log_line_prefix`, se descartó porque ese parámetro requiere recarga del servidor; el script pasó a usar `ALTER SYSTEM` con restauración explícita. |
| OpenCode, en sesión de análisis: reconstruir los hechos y proponer contención **solo a partir de** `docs/log_simulacro_anonimizado.txt`, sin contexto adicional del proyecto. | Respuesta íntegra conservada en `docs/respuesta_ia_incidente.md`. | El simulacro real produjo tres fallos, un éxito para el usuario sintético 40010, lectura de `id_usuario`/`eliminado` y un `GRANT admin_datos TO app_web` denegado. `ROLLBACK` dejó 0 usuarios sintéticos y 0 membresías nuevas. El análisis acertó la secuencia, pero afirmó erróneamente que `app_web` podía leer toda la tabla y trató `admin_datos` como `NOLOGIN`. La comparación y decisión humana están en `docs/informe_incidente.md`: fue una prueba contenida, no un incidente real. |

El log compartido con OpenCode sustituyó correos y contraseñas por marcadores. No se envió el archivo bruto ni registros personales de `usuario`.

## Parte D — Anonimización y equivalencia

| Herramienta y prompt relevante | Respuesta o artefacto | Validación y decisión humana |
|---|---|---|
| OpenCode: crear `usuario_anon` con nombres y correos sintéticos deterministas, celular nulo y contraseña inutilizable; conservar `rol`, `eliminado` y `created_at`, y generar agregados equivalentes por rol/mes/estado con `EXCEPT` bidireccional. | `sql/usuario_anon.sql`. | En DBeaver, `usuario` y `usuario_anon` dieron 20.009 filas cada una. Los cuatro grupos agregados coincidieron fila por fila y ambos `EXCEPT` devolvieron 0 filas. Los resultados lado a lado están en `docs/verificacion_equivalencia.md`. Se decidió compartir solo agregados: mantener ID y fecha exacta en la copia no garantiza anonimato irreversible de toda la tabla. |

## Error de IA más significativo

En la reconstrucción del incidente, OpenCode concluyó que un `SELECT id_usuario, eliminado FROM usuario` demostraba permiso de lectura sobre **toda** la tabla. Se detectó el error comparando la sentencia registrada con `sql/roles.sql`, que concede a `app_web` `SELECT` únicamente sobre esas dos columnas. Confundir acceso a columnas con acceso a `usuario.contrasena` habría llevado a describir una exposición de datos no demostrada y a recomendar una contención desproporcionada. Por eso se conservó la respuesta original, pero la decisión final se tomó con la matriz de privilegios y los resultados reales, no con esa inferencia.

## Historial Git y cierre

La revisión local del historial mostró commits legibles y separados para la Parte A (`4d7eb00`, roles y permisos) y la Parte B (`78ee9eb`, pruebas e informe de auditoría). Al redactar esta bitácora, los artefactos de las Partes C y D y este archivo aún no figuraban en `HEAD`: resta revisarlos, crear un commit descriptivo para el cierre y subirlo. No es necesario reescribir los commits anteriores.
