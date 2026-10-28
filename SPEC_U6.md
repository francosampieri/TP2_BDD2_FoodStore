# SPEC_U6 — Mantenimiento y recuperación de FoodStore

Entorno: PostgreSQL 17 en Windows. La base de origen es `foodstore`; la restauración de prueba utiliza exclusivamente una base nueva llamada `foodstore_restore_test`. La estructura real contiene `usuario`, no `cliente`. Los scripts se generan con apoyo de OpenCode, se revisan antes de ejecutarlos y se prueban manualmente antes de programar cualquier tarea.

| Tarea | Frecuencia propuesta | Condición de éxito y evidencia |
| --- | --- | --- |
| Respaldo lógico | Diaria | `backup_foodstore.ps1` genera un archivo custom `backups/foodstore_FECHA_HORA.dump`, registra inicio, fin y resultado en `logs/`, verifica el código de salida de `pg_dump`, el archivo no vacío y que `pg_restore --list` pueda leerlo. Si falla, termina con código distinto de cero. |
| Chequeo de salud | Diaria | `health_check.sql` registra fecha, tamaño de la base, conexiones, actividad, estado de tablas y consultas activas. |
| Revisión de mantenimiento | Semanal | `maintenance.sql` muestra tuplas vivas/muertas y fechas de autovacuum/ANALYZE; cualquier acción manual se justifica con esos datos. No se ejecuta `VACUUM FULL` como rutina. |
| Restauración de prueba | Semanal | El último respaldo se restaura en `foodstore_restore_test` sin modificar `foodstore`. Se comparan los conteos de `categoria`, `usuario`, `producto`, `pedido` y `detalle_pedido` registrados antes del respaldo; los controles de precio, stock, cantidad y precio unitario inválidos dan cero. |

Seguridad: nunca incluir contraseñas en scripts, logs o Git. Los archivos `.dump` y los logs con datos sensibles permanecen locales. El ensayo debe detenerse si `foodstore_restore_test` ya existe; no borrar ni sobrescribir ninguna base automáticamente. No ejecutar acciones destructivas sobre `foodstore`.

Objetivos del laboratorio: RPO previsto de hasta 24 horas con respaldo diario y RTO previsto menor de 20 minutos. En el simulacro, medir el RTO desde inmediatamente antes de crear la base de prueba hasta terminar las validaciones; calcular la antigüedad real del respaldo al iniciar el ensayo como RPO observado. Registrar fechas, tiempos, resultados, problemas y una mejora concreta en `informe_u6.pdf` (máximo una página). El respaldo no se considera verificado hasta restaurarlo y validar los datos.
