# Protocolo de seguridad — TP2 FoodStore

## Entorno de trabajo

- Motor: PostgreSQL 17.
- Cliente SQL: DBeaver.
- Base original: `foodstore`.
- Base exclusiva de trabajo para el TP2: `foodstore_tp2`.
- Los respaldos locales se guardan en `backups/` y no se suben a Git.

## 1. Copia de trabajo

No se ejecutan pruebas ni scripts del TP2 sobre `foodstore`.

La copia de trabajo se creó desde una conexión a la base administrativa `postgres`:

```sql
CREATE DATABASE foodstore_tp2 WITH TEMPLATE foodstore;
```

Antes de cada prueba, se verifica que la conexión activa sea la copia:

```sql
SELECT current_database();
```

El resultado debe ser `foodstore_tp2`.

## 2. Transacciones

Todo cambio de datos o estructura se prueba primero dentro de una transacción:

```sql
BEGIN;

-- Sentencias a verificar

ROLLBACK;
```

Se revisan los mensajes, las filas afectadas y las consultas de verificación antes de confirmar una operación. Solo se usa `COMMIT` en `foodstore_tp2` cuando el escenario necesita que otra sesión vea el cambio.

## 3. Respaldo

Antes de un cambio estructural, como `ALTER TABLE`, `CREATE TRIGGER` o una migración, se genera un respaldo de `foodstore_tp2`.

En DBeaver se usa `Tools → Backup`, formato `Custom`, con salida en la carpeta local `backups/`.

El respaldo inicial es `foodstore_tp2_inicial.backup`.