# Auditoría de cobertura - segunda entrega parcial del TPI

Esta auditoría compara los 14 criterios de la consigna con la evidencia disponible en el repositorio. **Cubierto** significa que hay un artefacto y un resultado documentado; **parcial** señala una evidencia o una ejecución que aún falta. No sustituye la revisión final ni el informe técnico de entrega.

| # | Criterio | Estado | Evidencia y observación |
| --- | --- | --- | --- |
| 1 | Esquema heredado, DF reales y FNBC | Cubierto | `specs/tp_u4/plan_fnbc_desnormalizacion.md`, `sql/tp_fnbc_control_lote.sql`, `docs/tp_u4/informe_tp_u4.md`. Se identifica `ResponsableControlID -> DepositoID`, se descompone en R1/R2 y se explica que DF1 no queda preservada automáticamente. |
| 2 | Migración reversible, especificada en Kiro, con plan de reversión | Cubierto | Parte 4 de `specs/tp_u4/plan_fnbc_desnormalizacion.md` y `sql/tpi_u4_migracion_reversible.sql`. En `foodstore_tp_u4_mig` se probó primero `ROLLBACK`: la validación dio 0/0 y ambas tablas consultadas con `to_regclass` quedaron ausentes. En la segunda ejecución se hizo `COMMIT`; quedaron 3 filas originales y 3 reconstruidas, con `EXCEPT` post-commit en 0/0. La reversión posterior está documentada sin borrar la fuente original. |
| 3 | Desnormalización controlada y salvaguardas | Cubierto | `sql/tp_desnormalizacion_top_categorias.sql` y `docs/tp_u4/informe_tp_u4.md`: vista materializada, índice único, refresco y límite de actualidad. Medición directa 4,335 ms frente a 1,561 ms sobre dos detalles del día; `EXCEPT` en 0/0. |
| 4 | Usuarios, roles y mínimo privilegio | Cubierto | `docs/kiro_roles_spec/spec_roles_tp_u5.md`, `sql/roles.sql`, `BITACORA.md`. Nueve comprobaciones de permisos y prueba reversible de pedido como `app_web`. |
| 5 | Auditoría y simulacro de acceso indebido | Cubierto | `sql/auditoria_test.sql`, `sql/simulacro_incidente.sql`, `docs/informe_auditoria.md`, `docs/informe_incidente.md` y extracto anonimizado. Tres fallos de autenticación, un éxito sintético, lectura acotada y `GRANT` rechazado; se documentó contención. |
| 6 | Auditoría de seguridad asistida por IA con decisión humana | Cubierto | `docs/respuesta_ia_incidente.md`, `docs/informe_incidente.md`, `BITACORA.md`. Se corrigieron inferencias de OpenCode sobre lectura de toda la tabla y tipo de rol. |
| 7 | Mantenimiento, respaldo programado y automatización | **Parcial** | `scripts/backup_foodstore.ps1`, `scripts/programar_backup_foodstore.ps1`, `sql/health_check.sql`, `sql/maintenance.sql` e `informe_u6.pdf` cubren respaldo manual, restauración, mantenimiento y la preparación de una tarea diaria. Por decisión del equipo, no se instaló la tarea en esta computadora ni se observó una ejecución automática. |
| 8 | Simulacro de desastre e informe post-incidente | Cubierto | `scripts/restore_test.ps1` e `informe_u6.pdf`: restauración en `foodstore_restore_test`, conteos 8/9/25/21/37, controles de integridad sin fallos, RTO observado 31,96 s y antigüedad estimada del respaldo 22 min 37 s (no pérdida real medida). |
| 9 | Modelo documental y consultas reales | Cubierto | `mongodb/pedidos_u7.json`, `mongodb/consultas_mongodb.js` y `docs/tp7/informe_tp7.md`. Cinco pedidos y ocho líneas importados; consultas ejecutadas en Compass. |
| 10 | Comparación documental/relacional | Cubierto | `sql/consultas_postgresql_u7.sql` y `docs/tp7/informe_tp7.md`. Coincidieron los IDs de las consultas comparadas; PostgreSQL se eligió como fuente transaccional y MongoDB como posible proyección de lectura. |
| 11 | SQLite con spec Kiro y scripts OpenCode | Cubierto | `docs/kiro/tp8/` y `movil/`: esquema `STRICT`, CSV, UPSERT, borradores y cola de solicitudes. |
| 12 | Sincronización simulada y conflictos | Cubierto | `movil/semaforo.sql`, `movil/datos_casos.sql`, `docs/tp8/informe_tp8.md`. C2 conflicto de precio y reenvío con nuevo UUID, C3 stock, C4 baja, C5 aprobación simulada, C6 idempotencia y C7 atomicidad. PostgreSQL conservó 21 pedidos y stock total 785. |
| 13 | Code review final de U1-U8 y decisiones humanas | Cubierto | `docs/tp8/informe_tp8.md` y `docs/tp8/bitacora_ia.md`. Se registró la decisión sobre H1-H6, m1-m2 y D1-D2; H2 se reprodujo y corrigió, H4 se descartó con plan real y H6 se corrigió y probó. |
| 14 | Capa de datos completa y lista para defensa | **Parcial** | `docs/tpi/informe_tpi_segunda_entrega.md`, `docs/tpi/duia_tpi_segunda_entrega.md` y la sección 7 del README consolidan los artefactos. Persiste el límite del criterio 7: la ejecución automática del respaldo no fue verificada. |

## Orden de cierre recomendado

1. Revisar y versionar los archivos de la segunda entrega.
2. Entregar el PDF del informe y el enlace al repositorio. La automatización del respaldo debe presentarse como preparada, no como ejecutada.

## Límites de esta auditoría

La revisión fue documental y estática. No se ejecutaron de nuevo SQL, PowerShell, MongoDB ni SQLite para realizarla. Los resultados indicados provienen de los informes de cada unidad y de las comprobaciones comunicadas durante esos trabajos.
