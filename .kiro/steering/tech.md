# Tech Stack

## Database
- **PostgreSQL 17** — sole technology in this project; no application layer exists.
- All logic lives in the database: schemas, triggers, functions, views, and stored procedures.

## PostgreSQL Features Used
- **Custom ENUM types**: `rol`, `estado_pedido`, `forma_pago`
- **Triggers**: `BEFORE INSERT/UPDATE` (row-level) for subtotal calculation; `AFTER INSERT/UPDATE` (statement-level) with **Transition Tables** (`REFERENCING NEW TABLE AS`) for total recalculation
- **Stored procedure**: `sp_crear_pedido` uses `LANGUAGE plpgsql`, validates stock, and raises exceptions for business-rule violations. An exception aborts the active transaction, so the caller must use `ROLLBACK`.
- **Window functions**: `RANK() OVER (...)` used in analytical queries
- **JSONB**: items array passed to `sp_crear_pedido` as `JSONB`
- **Indexes**: performance indexes defined in `schema.sql`

## Client Tools

- **DBeaver** is the SQL client used for this project.
- PostgreSQL 17 native tools are available for backups, including `pg_dump`.

## Common Commands

### Create the original database (run once)

```sql
CREATE DATABASE foodstore;

### Script execution order (must be sequential)
```
1. schema.sql         -- ENUMs, tables, indexes
2. Objects.sql        -- views, functions, triggers, stored procedure
3. data.sql           -- seed data; depends on the triggers
```

### Test transactional procedure
```sql
-- Happy path
CALL sp_crear_pedido(2, 'EFECTIVO', '[{"producto_id": 1, "cantidad": 2}]'::jsonb);

-- Rollback: insufficient stock
CALL sp_crear_pedido(2, 'TARJETA', '[{"producto_id": 5, "cantidad": 9999}]'::jsonb);

-- Rollback: product is logically deleted
CALL sp_crear_pedido(2, 'TARJETA', '[{"producto_id": 4, "cantidad": 1}]'::jsonb);
```

### Verify trigger automation
```sql
SELECT * FROM v_pedidos_resumen WHERE id_pedido = 1;
SELECT * FROM v_pedido_detalle   WHERE id_pedido = 1;
```
