-- CATEGORIAS (ids 1-7)
INSERT INTO categoria (nombre_categoria, descripcion_categoria) VALUES
('Pizzas',        'Pizzas artesanales a la piedra'),
('Empanadas',     'Empanadas caseras horneadas'),
('Hamburguesas',  'Hamburguesas smash y clasicas'),
('Bebidas',       'Bebidas frias con y sin alcohol'),
('Postres',       'Postres caseros'),
('Pastas',        'Pastas frescas artesanales');

-- Categoria dada de baja logica (para probar v_categorias_vigentes)
INSERT INTO categoria (nombre_categoria, descripcion_categoria, eliminado) VALUES
('Ensaladas', 'Linea de ensaladas (descontinuada)', TRUE);

-- PRODUCTOS (ids 1-24)
-- id_categoria: 1=Pizzas, 2=Empanadas, 3=Hamburguesas, 4=Bebidas, 5=Postres, 6=Pastas
INSERT INTO producto (nombre_producto, precio, descripcion_producto, stock, disponible, id_categoria) VALUES
('Muzzarella',      3500.00, 'Pizza clasica de muzzarella',          20, TRUE,  1),
('Napolitana',      3800.00, 'Pizza con tomate, ajo y albahaca',     15, TRUE,  1),
('Fugazzeta',       3900.00, 'Pizza de cebolla',                     10, TRUE,  1),
('Especial',        4200.00, 'Pizza especial de la casa',             5, TRUE,  1),
('Carne',            350.00, 'Empanada de carne cortada a cuchillo', 100, TRUE, 2),
('Pollo',            350.00, 'Empanada de pollo',                    100, TRUE, 2),
('Jamon y queso',    380.00, 'Empanada de jamon y queso',             80, TRUE, 2),
('Verdura',          320.00, 'Empanada de acelga y queso',            60, TRUE, 2),
('Clasica',         2800.00, 'Hamburguesa simple con papas',          30, TRUE, 3),
('Doble Cheddar',   3400.00, 'Doble carne con cheddar',               25, TRUE, 3),
('Bacon',           3600.00, 'Hamburguesa con bacon crocante',        20, TRUE, 3),
('Veggie',          3000.00, 'Hamburguesa de garbanzos',              15, TRUE, 3),
('Coca Cola',       1200.00, 'Gaseosa linea Coca Cola 500ml',         50, TRUE, 4),
('Agua',              800.00, 'Agua mineral 500ml',                   60, TRUE, 4),
('Cerveza',         1500.00, 'Cerveza rubia 473ml',                   40, TRUE, 4),
('Jugo de Naranja', 1000.00, 'Jugo exprimido natural',                10, TRUE, 4),
('Flan',            1200.00, 'Flan casero con dulce de leche',        25, TRUE, 5),
('Helado',          1400.00, 'Copa de helado x2 bochas',              20, TRUE, 5),
('Brownie',         1300.00, 'Brownie con nuez',                      30, TRUE, 5),
('Tiramisu',        1600.00, 'Postre italiano',                        8, FALSE,5),
('Noquis',          2600.00, 'Noquis de papa caseros',                20, TRUE, 6),
('Ravioles',        2900.00, 'Ravioles de ricota y jamon',            18, TRUE, 6),
('Sorrentinos',     3100.00, 'Sorrentinos de jamon y muzzarella',      0, TRUE, 6),
('Lasagna',         3300.00, 'Lasagna de carne',                      12, TRUE, 6);

-- Productos dados de baja logica (para probar v_productos_vigentes)
UPDATE producto SET eliminado = TRUE WHERE id_producto IN (4, 16); -- Especial, Jugo de Naranja

-- USUARIOS (ids 1-8)
INSERT INTO usuario (nombre_usuario, apellido, mail, celular, contrasena, rol) VALUES
('Admin',    'Garcia',     'admin@foodstore.com',     '2610000001', '111', 'ADMIN'),
('Ana',      'Gomez',      'ana.gomez@mail.com',      '2611111111', '222', 'USUARIO'),
('Juan',     'Perez',      'juan.perez@mail.com',     '2612222222', '333', 'USUARIO'),
('Maria',    'Lopez',      'maria.lopez@mail.com',    '2613333333', '444', 'USUARIO'),
('Carlos',   'Fernandez',  'carlos.fdz@mail.com',     '2614444444', '555', 'USUARIO'),
('Lucia',    'Rodriguez',  'lucia.rodriguez@mail.com','2615555555', '666', 'USUARIO'),
('Pedro',    'Sosa',       'pedro.sosa@mail.com',     '2616666666', '777', 'USUARIO'),
('Sofia',    'Torres',     'sofia.torres@mail.com',   '2617777777', '888', 'USUARIO');

-- PEDIDOS (ids 1-20)
-- El total no se inserta: lo calcula trg_total_ins luego de insertar cada detalle_pedido.
INSERT INTO pedido (fecha, estado, forma_pago, id_usuario) VALUES
('2026-02-10', 'TERMINADO',  'EFECTIVO',      8), -- (1)  
('2026-03-05', 'TERMINADO',  'EFECTIVO',      2), -- (2)
('2026-03-12', 'TERMINADO',  'TARJETA',       3), -- (3)
('2026-04-02', 'TERMINADO',  'TRANSFERENCIA', 4), -- (4)
('2026-04-18', 'TERMINADO',  'EFECTIVO',      2), -- (5)
('2026-04-25', 'CANCELADO',  'TARJETA',       5), -- (6)
('2026-05-03', 'TERMINADO',  'EFECTIVO',      6), -- (7)
('2026-05-14', 'TERMINADO',  'TRANSFERENCIA', 3), -- (8)
('2026-05-30', 'TERMINADO',  'TARJETA',       7), -- (9)
('2026-06-10', 'TERMINADO',  'EFECTIVO',      2), -- (10)
('2026-06-15', 'CONFIRMADO', 'TARJETA',       4), -- (11)
('2026-06-28', 'TERMINADO',  'EFECTIVO',      6), -- (12)
('2026-07-04', 'TERMINADO',  'TRANSFERENCIA', 5), -- (13)
('2026-07-11', 'TERMINADO',  'TARJETA',       3), -- (14)
('2026-07-20', 'PENDIENTE',  'EFECTIVO',      7), -- (15)
('2026-08-01', 'TERMINADO',  'TARJETA',       2), -- (16)
('2026-08-10', 'CONFIRMADO', 'TRANSFERENCIA', 6), -- (17)
('2026-08-15', 'PENDIENTE',  'EFECTIVO',      4), -- (18)
('2026-08-18', 'TERMINADO',  'TARJETA',       5), -- (19)
('2026-08-19', 'TERMINADO',  'TARJETA',       5); -- (20) se marca eliminado mas abajo

-- Se da de baja al usuario 8 (su pedido historico #1 queda intacto)
UPDATE usuario SET eliminado = TRUE WHERE id_usuario = 8;

-- DETALLE_PEDIDO
-- No se informan precio_unitario ni subtotal: los completa trg_subtotal.

INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad) VALUES
(1, 1, 1),  (1, 14, 2),
(2, 1, 2),  (2, 13, 2),
(3, 9, 1),  (3, 14, 3),
(4, 2, 1),  (4, 5, 6),
(5, 10, 2), (5, 17, 2),
(6, 11, 1),
(7, 3, 2),  (7, 15, 4),
(8, 6, 8),  (8, 18, 1),
(9, 12, 2), (9, 21, 2),
(10, 1, 1), (10, 7, 5), (10, 13, 1),
(11, 22, 2),
(12, 9, 3), (12, 14, 2),
(13, 24, 1), (13, 8, 4),
(14, 2, 2),
(15, 19, 3),
(16, 10, 1), (16, 15, 2),
(17, 21, 1), (17, 17, 2),
(18, 5, 4),
(19, 11, 2), (19, 13, 3),
(20, 3, 1);