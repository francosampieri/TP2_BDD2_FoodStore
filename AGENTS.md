# AGENTS.md — FoodStore

## What this is

PostgreSQL 17 database project for a food-ordering system ("FoodStore"). All logic lives in `sql/` scripts. There is no application code, no build system, no test runner — execution is manual via DBeaver.

## Environment setup

`schema.sql` contains `CREATE DATABASE FoodStore;` on its first line, but this statement must be executed **separately** from a connection to the `postgres` database. After it runs, PostgreSQL normalizes the name to `foodstore` (lowercase). You must then **manually connect to `foodstore`** before running the rest of the schema and the remaining scripts.

For TP2 work, **do not recreate `foodstore`**. All work and testing is done exclusively on `foodstore_tp2`.

## Script execution order

### Mandatory initial load (in this order, on a clean database)

1. `sql/schema.sql` — enums, tables, indexes (skip the `CREATE DATABASE` line if the DB already exists)
2. `sql/Objects.sql` — views, functions, triggers, stored procedure
3. `sql/data.sql` — seed data

### Selective / advanced scripts

4. `sql/queries.sql` — use-case queries and analytics (contains INSERT/UPDATE that modify data)
5. `sql/transacciones.sql` — transaction/isolation demos (requires concurrent sessions; modifies data)

These two scripts should only be run on `foodstore_tp2`, never directly on `foodstore`.

## Key patterns to preserve

- **Soft delete**: every table has an `eliminado` boolean column. Each view filters only the deleted rows from its own scope — a view does not propagate `eliminado` checks to related tables it joins.
- **Trigger-computed fields**: `trg_subtotal` auto-fills `precio_unitario` and `subtotal` on `detalle_pedido` inserts/updates. `trg_total_ins`/`trg_total_upd` recalculate `pedido.total` via transition tables. Do not manually set these values in INSERT statements.
- **Transactional order creation**: `sp_crear_pedido(p_id_usuario, p_forma_pago, p_items JSONB)` handles the full order lifecycle (validate user, create pedido, loop items with `SELECT ... FOR UPDATE` on stock, insert detalles, deduct stock).

## Gotchas

- `sp_crear_pedido` takes JSONB: `'[{"producto_id":1,"cantidad":2}]'::jsonb`. It raises exceptions on failure; these abort the active transaction and the user must issue `ROLLBACK` explicitly.
- `transacciones.sql` scenarios 3 and 4 require two concurrent sessions — two DBeaver connections or two psql terminals.
- Products with `disponible = FALSE` or `eliminado = TRUE` will cause `sp_crear_pedido` to throw before inserting any details.
- User id 8 is soft-deleted in seed data but has historical order #1.
