# Declaración de Uso de Inteligencia Artificial - TP8 FoodStore

**Equipo:** Franco Sampieri, Mauro Di Pietro, Tomas Martinez y Renzo Victoria.

Usamos **Kiro** para especificar los requisitos y el diseño antes de programar. Usamos **OpenCode** para generar los primeros scripts SQLite y PostgreSQL, aplicar correcciones solicitadas tras revisarlos y realizar una revisión estática global en el agente Plan. Usamos **Codex** como herramienta adicional para revisar el código, comparar los CSV y ejecutar pruebas locales de SQLite.

No aceptamos las salidas de IA sin comprobación. Por ejemplo, rechazamos productos de prueba que solo existían en SQLite, corregimos un error de sintaxis del script de casos y reemplazamos una comprobación de idempotencia que daba un supuesto resultado correcto antes de ejecutar el intento duplicado. Las pruebas finales de SQLite confirmaron los estados del semáforo, los errores de integridad y la conservación de las claves foráneas.

La revisión global de OpenCode señaló, entre otros puntos, un borrador vacío que permanece pendiente y un supuesto problema con un índice parcial. Comprobamos el primero en SQLite y descartamos la conclusión general del segundo usando el plan real medido en TP5. Las decisiones y resultados observados se detallan en `docs/tp8/bitacora_ia.md` y `docs/tp8/informe_tp8.md`. El equipo asume la responsabilidad por el contenido entregado y por explicar los scripts en la defensa.
