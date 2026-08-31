# Project Structure

```
TPN1_BDD_2_FoodStore/
├── sql/
│   ├── schema.sql        # ENUMs, tables, indexes — run first
│   ├── Objects.sql       # Views, functions, triggers, stored procedure — run second
│   ├── data.sql          # Seed/test data — run third
│   └── queries.sql       # Use-case queries (epics) and analytical reports —
│   └── transacciones.sql # Transaction and concurrency examples; run selectively 
run fourth
├── backups/              # Local backups; ignored by Git
├── .kiro/
│   └── steering/         # AI assistant context files
├── README.md             # Setup instructions and test scenarios
└── _Proyecto FoodStore.docx  # Original project specification document
```

## SQL Layer Organization

| File | Responsibility |
|---|---|
| `schema.sql` | DDL only — ENUMs (`rol`, `estado_pedido`, `forma_pago`), all tables with constraints, performance indexes |
| `Objects.sql` | Programmable objects — 4 views, helper function `calcular_total_pedido`, triggers `trg_subtotal` / `trg_total_ins` / `trg_total_upd`, procedure `sp_crear_pedido` |
| `data.sql` | DML seed data — 7 categories, 24 products, 8 users, 20 orders, all order line items |
| `queries.sql` | Optional test/reference queries; it modifies data and must only run selectively on `foodstore_tp2` |

## Naming Conventions

- **Tables**: singular snake_case — `categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`
- **Views**: prefixed `v_` — `v_productos_vigentes`, `v_pedidos_resumen`, `v_pedido_detalle`, `v_categorias_vigentes`
- **Functions**: prefixed `fn_` — `fn_set_subtotal`, `fn_recalcular_total`
- **Triggers**: prefixed `trg_` — `trg_subtotal`, `trg_total_ins`, `trg_total_upd`
- **Stored procedures**: prefixed `sp_` — `sp_crear_pedido`
- **Primary keys**: `id_<table>` (e.g. `id_producto`, `id_pedido`)
- **Foreign keys**: `id_<referenced_table>` (e.g. `id_categoria` on `producto`)
- **Procedure parameters**: prefixed `p_` (e.g. `p_id_usuario`)
- **Local variables**: prefixed `v_` (e.g. `v_id_pedido`, `v_stock`)
- **Soft delete column**: always named `eliminado BOOLEAN NOT NULL DEFAULT FALSE`
