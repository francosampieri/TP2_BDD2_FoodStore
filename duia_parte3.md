# DUIA — Parte 3: Lectura crítica de scripts

## Herramienta

- Codex (GPT-5), utilizado para analizar el efecto real de dos scripts antes de ejecutarlos y proponer sus correcciones.

## Consulta utilizada

Se solicitó identificar qué filas afectan realmente dos scripts SQL genéricos de la consigna, explicar por qué no cumplen el objetivo indicado y reescribirlos de forma segura.

## Qué generó la IA

- Análisis de que el primer `UPDATE` no tiene `WHERE` y alcanza a todas las funciones.
- Análisis del riesgo de `NOT IN` cuando la subconsulta contiene `NULL`.
- Versiones corregidas mediante un predicado explícito y `NOT EXISTS`.
- Adaptación adicional al modelo de baja lógica de FoodStore.

## Qué se aceptó

- La identificación del alcance total del primer `UPDATE`.
- La explicación de la semántica de `NOT IN` frente a `NULL`.
- La sustitución de `NOT IN` por `NOT EXISTS` para el esquema genérico.

## Qué se modificó o se dejó condicionado

- Para el Script 1 no se inventó una columna definitiva para detectar una función retirada: la corrección muestra `fecha` como supuesto explícito y exige adaptarla al esquema real antes de ejecutarla.
- Para el Script 2 se agregó una adaptación a FoodStore que usa baja lógica (`eliminado`) en lugar de `DELETE` físico.

## Verificación realizada

Los scripts se analizaron de manera estática y **no se ejecutaron**, porque el objetivo es detectar el efecto riesgoso antes de tocar datos. La corrección propuesta se contrastó con las reglas del esquema FoodStore: nombres de columnas, baja lógica y productos vigentes.

## Archivo relacionado

- `ejercicio_lectura_critica.md`
