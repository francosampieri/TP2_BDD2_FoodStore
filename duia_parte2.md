# DUIA — Parte 2: Concurrencia

## Herramienta

- Codex (GPT-5), utilizado para explicar los fenómenos observados y proponer el nivel de aislamiento o mecanismo de bloqueo a verificar.

## Consulta utilizada

Se solicitó una explicación para cada escenario observado en PostgreSQL 17 sobre `foodstore_tp2`: lectura no repetible, lectura fantasma y espera por bloqueo. También se solicitó indicar qué nivel de aislamiento o mecanismo evita o controla cada caso.

## Qué generó la IA

- Explicación de que `READ COMMITTED` usa una nueva instantánea por sentencia.
- Propuesta de `REPEATABLE READ` para evitar lecturas no repetibles y fantasma en estos experimentos de PostgreSQL.
- Explicación de que `SELECT ... FOR UPDATE` toma un bloqueo de fila y hace esperar a una sesión concurrente.
- Secuencias de comandos para ejecutar en dos sesiones de DBeaver.

## Qué se aceptó

- Las secuencias de dos sesiones para los tres escenarios.
- La propuesta de comprobar `READ COMMITTED` frente a `REPEATABLE READ`.
- La explicación del bloqueo de fila con `FOR UPDATE`.

## Qué se modificó o descartó, y por qué

- Se usaron los valores y nombres reales observados durante el laboratorio (`stock` 20/19 y conteos 3/4) en lugar de valores genéricos.
- Los productos usados para la lectura fantasma se marcaron como eliminados después de cada prueba para no dejar filas vigentes de laboratorio.
- No se realizó el interbloqueo real porque era opcional y los tres escenarios obligatorios ya estaban verificados.

## Verificación realizada

Las explicaciones se verificaron en PostgreSQL 17 con dos sesiones de DBeaver sobre `foodstore_tp2`:

| Escenario | Resultado esperado por la IA | Resultado real |
|---|---|---|
| Lectura no repetible | `READ COMMITTED` cambia la segunda lectura; `REPEATABLE READ` conserva la instantánea | 20 → 19 en `READ COMMITTED`; 20 → 20 en `REPEATABLE READ` |
| Lectura fantasma | El `COUNT` cambia en `READ COMMITTED` y no cambia en `REPEATABLE READ` | 3 → 4 en `READ COMMITTED`; 3 → 3 en `REPEATABLE READ` |
| Espera por bloqueo | B espera por el `FOR UPDATE` de A y continúa al liberar A el bloqueo | Confirmado: B quedó esperando y se destrabó luego del `COMMIT` de A |

## Archivo relacionado

El registro detallado de comandos, salidas y conclusiones está en `informe_concurrencia.md`.
