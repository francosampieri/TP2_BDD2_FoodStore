// TP7 FoodStore: ejecutar cada consulta por separado en el shell integrado de Compass.
// Base: foodstore_nosql; coleccion: pedidos. El archivo pedidos_u7.json se importa una sola vez.
// _id conserva pedido.id_pedido. fecha es texto YYYY-MM-DD porque el origen usa DATE.
// Los importes del JSON usan Decimal128, no Double.

// Control previo: deben existir exactamente los cinco pedidos seleccionados.
db.getSiblingDB("foodstore_nosql").pedidos.countDocuments({});

// a) Todos los pedidos: identificador y estado. Esperado: 2, 3, 6, 11, 12.
db.getSiblingDB("foodstore_nosql").pedidos.find(
  {}, { _id: 1, estado: 1 }
).sort({ _id: 1 }).toArray();

// b) Estado TERMINADO. Esperado: 2, 3, 12.
db.getSiblingDB("foodstore_nosql").pedidos.find(
  { estado: "TERMINADO" }, { _id: 1, estado: 1 }
).sort({ _id: 1 }).toArray();

// c) Pedidos con el producto 9 en alguna linea. Esperado: 3, 12.
db.getSiblingDB("foodstore_nosql").pedidos.find(
  { "items.id_producto": 9 }, { _id: 1 }
).sort({ _id: 1 }).toArray();

// d) Total estrictamente mayor que 6000.00. Se eligio el umbral para
// separar dos pedidos (2 y 12) de los otros tres en esta muestra.
db.getSiblingDB("foodstore_nosql").pedidos.find(
  { total: { $gt: Decimal128("6000.00") } }, { _id: 1, total: 1 }
).sort({ _id: 1 }).toArray();
