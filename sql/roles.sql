-- ============================================================
-- ROLES Y PRIVILEGIOS — TP Unidad 5, Parte A
-- Base objetivo: foodstore_tp_u5 (copia con el ESQUEMA COMPLETO:
--   schema.sql + Objects.sql + restricciones.sql
--   + views_tp5.sql + vista_materializada_tp5.sql)
-- Motor: PostgreSQL 17.
--
-- Opción adoptada: SECURITY INVOKER (Opción A de la spec).
--   NO se modifica Objects.sql: ni sp_crear_pedido ni los triggers
--   declaran SECURITY DEFINER. Por lo tanto el rol llamador necesita
--   permisos DIRECTOS sobre cada objeto que toca el flujo.
--   Limitación declarada: los permisos no "enforcean" el uso del
--   procedimiento; app_web puede técnicamente insertar/actualizar por
--   su cuenta (ver spec §5.1). Es el costo elegido de la Opción A.
--
-- SIN contraseñas: los dos roles LOGIN se crean con PASSWORD NULL.
--   La credencial se define FUERA de Git, por ejemplo:
--     ALTER ROLE app_web     WITH PASSWORD '...';
--     ALTER ROLE admin_datos WITH PASSWORD '...';
--
-- Sin comandos destructivos: no hay DROP ROLE, DROP OWNED ni
--   REASSIGN OWNED, y no se tocan otras bases.
--
-- DOS BLOQUES DE DISTINTO ALCANCE:
--   BLOQUE 1 → creación de roles y membresías: alcance de TODO EL
--              SERVIDOR (se ejecuta conectado a cualquier base).
--   BLOQUE 2 → permisos sobre objetos: alcance de la base
--              foodstore_tp_u5 (conectarse a ella antes de correr).
--   No ejecutar el BLOQUE 2 contra foodstore (producción) ni contra
--   foodstore_tp2.
-- ============================================================


-- ============================================================
-- BLOQUE 1 — CREACIÓN DE ROLES Y MEMBRESÍAS
--            ALCANCE: TODO EL SERVIDOR (cluster-wide)
-- Ejecutar UNA vez, conectado a cualquier base (p. ej. postgres).
-- CREATE ROLE y GRANT <rol> TO <rol> son metadatos del cluster.
-- Idempotencia: si los roles ya existen, CREATE ROLE falla; no se
-- incluye DROP para no borrar roles con permisos vivos.
-- ============================================================

-- ---- 1.1 Cuatro roles de grupo (NOLOGIN) ----

-- Lectura de catálogo y vistas de consulta general.
CREATE ROLE rol_app_lectura   NOLOGIN;

-- Creación de pedidos vía procedimiento. Incluye rol_app_lectura.
CREATE ROLE rol_app_escritura NOLOGIN;

-- Diagnóstico y consultas operativas. NO crea ni modifica datos de negocio.
CREATE ROLE rol_soporte       NOLOGIN;

-- Acceso exclusivo a vistas de reporte y a la vista materializada.
CREATE ROLE rol_reportes      NOLOGIN;

-- ---- 1.2 Dos roles LOGIN (sin contraseña) ----

-- Usuario de la aplicación web de pedidos.
CREATE ROLE app_web    LOGIN PASSWORD NULL;

-- Administración operativa (soporte + reportes), sin acceso a contraseñas.
CREATE ROLE admin_datos LOGIN PASSWORD NULL;

-- ---- 1.3 Membresías ----

-- La escritura hereda toda la lectura; la app web hereda la escritura.
GRANT rol_app_lectura   TO rol_app_escritura;
GRANT rol_app_escritura TO app_web;

-- El administrador de datos combina soporte y reportes.
GRANT rol_soporte       TO admin_datos;
GRANT rol_reportes      TO admin_datos;


-- ============================================================
-- BLOQUE 2 — PERMISOS
--            ALCANCE: base foodstore_tp_u5
-- Conectarse PRIMERO a esa base (\c foodstore_tp_u5 en psql).
-- Requiere que la base contenga el esquema completo; si falta alguna
-- vista, función o procedimiento, el GRANT/REVOKE correspondiente
-- falla y hay que cargar antes el script faltante.
-- ============================================================

-- ---- 2.1 Esquema ----
-- USAGE sobre public es imprescindible para acceder a los objetos.
-- rol_app_escritura lo hereda de rol_app_lectura.
GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_soporte, rol_reportes;

-- CREATE en public queda denegado a todos (§3.1): no se otorga y se
-- revoca explícitamente de PUBLIC y de los roles de aplicación.
REVOKE CREATE ON SCHEMA public
    FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;

-- ---- 2.2 Tablas base ----

-- categoria: catálogo de solo lectura para la app y para soporte.
GRANT SELECT ON categoria TO rol_app_lectura, rol_soporte;

-- producto: lectura de catálogo; la app solo puede modificar stock.
GRANT SELECT ON producto TO rol_app_lectura, rol_soporte;
GRANT UPDATE (stock) ON producto TO rol_app_escritura;
-- Nota: UPDATE (stock) es necesario además por el bloqueo de fila que
-- usa sp_crear_pedido (SELECT stock, disponible ... FOR UPDATE): en
-- PostgreSQL, una cláusula FOR UPDATE exige, además de SELECT, el
-- privilegio UPDATE sobre al menos una columna de la tabla.

-- usuario: alta sensibilidad. Se parte de revocar PUBLIC y se conceden
-- SOLO columnas concretas; contrasena y celular no se otorgan a ningún
-- rol de aplicación.
REVOKE ALL ON usuario FROM PUBLIC;
REVOKE SELECT (contrasena) ON usuario FROM PUBLIC;
REVOKE SELECT (celular)    ON usuario FROM PUBLIC;

-- app: únicamente lo que sp_crear_pedido valida internamente.
GRANT SELECT (id_usuario, eliminado) ON usuario TO rol_app_escritura;

-- soporte: diagnóstico operativo, sin contrasena ni celular.
GRANT SELECT (id_usuario, nombre_usuario, apellido, mail, rol, eliminado, created_at)
      ON usuario TO rol_soporte;
REVOKE SELECT (contrasena) ON usuario FROM rol_soporte;
REVOKE SELECT (celular)    ON usuario FROM rol_soporte;

-- pedido: lectura general; escritura acotada a columnas.
--   INSERT acotado a lo que sp_crear_pedido enumera explícitamente.
--   UPDATE incluye total porque fn_recalcular_total (trigger INVOKER)
--   escribe pedido.total bajo el rol del llamador.
REVOKE ALL ON pedido FROM PUBLIC;
GRANT SELECT ON pedido TO rol_app_lectura, rol_soporte;
GRANT INSERT (id_usuario, forma_pago) ON pedido TO rol_app_escritura;
GRANT UPDATE (estado, forma_pago, eliminado, total) ON pedido TO rol_app_escritura;

-- detalle_pedido: lectura general; escritura acotada a columnas.
--   El INSERT enumera solo las columnas del procedimiento; el trigger
--   BEFORE fn_set_subtotal completa precio_unitario y subtotal sobre la
--   fila NEW, lo que NO exige privilegio INSERT sobre esas columnas.
REVOKE ALL ON detalle_pedido FROM PUBLIC;
GRANT SELECT ON detalle_pedido TO rol_app_lectura, rol_soporte;
GRANT INSERT (id_pedido, id_producto, cantidad) ON detalle_pedido TO rol_app_escritura;
GRANT UPDATE (eliminado) ON detalle_pedido TO rol_app_escritura;

-- ---- 2.3 Vistas regulares ----
-- rol_app_escritura las cubre por herencia de rol_app_lectura.
GRANT SELECT ON v_productos_vigentes,
                v_pedidos_resumen,
                v_pedido_detalle,
                v_categorias_vigentes,
                v_tp5_productos_categoria,
                v_tp5_detalle_pedido_productos
    TO rol_app_lectura, rol_soporte;

-- v_tp5_pedidos_usuario expone mail del usuario: solo soporte.
GRANT SELECT ON v_tp5_pedidos_usuario TO rol_soporte;

-- ---- 2.4 Vista materializada ----
GRANT SELECT ON mv_tp5_facturacion_categoria_mes
    TO rol_soporte, rol_reportes;
-- MAINTAIN NO se concede (§3.4): el REFRESH queda reservado al owner
-- de la vista materializada. Sin requisito explícito no se delega.

-- ---- 2.5 Rutinas ----
-- PostgreSQL otorga EXECUTE a PUBLIC por defecto al crear cada rutina.
-- Se revoca en TODAS las rutinas existentes y se otorga solo lo mínimo.
REVOKE EXECUTE ON FUNCTION  calcular_total_pedido(BIGINT)                 FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION  fn_set_subtotal()                            FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION  fn_recalcular_total()                        FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION  fn_check_estado_transition()                 FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION  fn_check_categoria_baja_logica()             FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB)   FROM PUBLIC;

-- calcular_total_pedido: la invoca fn_recalcular_total (INVOKER) bajo el
-- rol del llamador; soporte la usa además para diagnóstico (es STABLE).
GRANT EXECUTE ON FUNCTION calcular_total_pedido(BIGINT)
    TO rol_app_escritura, rol_soporte;

-- sp_crear_pedido: único punto de entrada válido para crear pedidos.
GRANT EXECUTE ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB)
    TO rol_app_escritura;

-- Las funciones de trigger (fn_set_subtotal, fn_recalcular_total,
-- fn_check_estado_transition, fn_check_categoria_baja_logica) no se
-- otorgan a ningún rol de aplicación: los roles nunca las invocan
-- directamente y sus efectos corren en el contexto de la sentencia DML.

-- ---- 2.6 ALTER DEFAULT PRIVILEGES — rutinas futuras ----
-- Ejecutar conectado a foodstore_tp_u5 COMO el rol que creará las
-- rutinas futuras (el que correrá CREATE FUNCTION / CREATE PROCEDURE).
-- Sin cláusula FOR ROLE, la sentencia aplica al rol actual: afecta
-- únicamente a las rutinas FUTURAS creadas por ESE rol en ESA base.
-- No toca las rutinas ya existentes (esas se ajustan en §2.5) ni
-- ninguna otra base.
--
-- Se revoca el EXECUTE que PostgreSQL concede a PUBLIC por defecto al
-- crear una rutina: así las funciones y procedimientos futuros nacen
-- sin acceso público y deben otorgarse de forma explícita.
--
-- Si posteriormente OTRO rol crea rutinas en esta base, sus privilegios
-- por defecto hay que configurarlos por separado (con una cláusula
-- FOR ROLE apuntando a ese rol, o conectándose como él): esta sentencia
-- no cubre a otros creadores.
--
-- Política: NO se otorga SELECT sobre todas las tablas futuras
-- (violaría el mínimo acceso); cada tabla nueva recibe permisos
-- explícitos al crearse.
ALTER DEFAULT PRIVILEGES
    REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
-- ============================================================
