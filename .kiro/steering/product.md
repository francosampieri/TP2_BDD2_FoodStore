# FoodStore — Product Overview

FoodStore is a relational database system for managing a gastronomic order platform. It models the full lifecycle of food orders: product catalog management (organized by categories), user accounts with role-based access, order creation with line-item details, and stock control.

## Core Business Concepts

- **Categorías** — product groupings (Pizzas, Empanadas, Hamburguesas, Bebidas, Postres, Pastas).
- **Productos** — items with price, stock, availability flag, and a parent category.
- **Usuarios** — customers and admins identified by role (`ADMIN` / `USUARIO`).
- **Pedidos** — orders tied to a user, with a payment method (`EFECTIVO`, `TARJETA`, `TRANSFERENCIA`) and a lifecycle state (`PENDIENTE`, `CONFIRMADO`, `TERMINADO`, `CANCELADO`).
- **Detalle_Pedido** — line items linking an order to products with quantity, unit price (snapshotted at insert), and subtotal.

## Key Business Rules

- The project uses logical deletion as its data-retention convention: application-level removals set `eliminado = TRUE`.
- Each `detalle_pedido.subtotal` and each `pedido.total` are computed automatically by database triggers and should not be assigned manually.
- The application should create orders through the `sp_crear_pedido` stored procedure to validate stock and keep order creation atomic. This is a project convention; direct SQL can bypass it.
- `v_productos_vigentes` and `v_categorias_vigentes` filter logically deleted products/categories. `v_pedidos_resumen` filters deleted orders, and `v_pedido_detalle` filters deleted order-detail rows.
