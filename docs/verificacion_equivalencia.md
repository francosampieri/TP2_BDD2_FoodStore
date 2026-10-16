# Unidad 5 — Verificación de equivalencia de `usuario_anon`

La tabla `usuario_anon` se creó y cargó con `sql/usuario_anon.sql` en `foodstore_tp_u5`. Las consultas se ejecutaron manualmente en DBeaver, en la misma sesión y zona horaria (`-03`). La tabla original y la anonimizada tenían **20.009 filas** cada una.

## Resultados agregados, lado a lado

| Rol | Mes de alta (-03) | Eliminado | `usuario` | `usuario_anon` |
|---|---|---:|---:|---:|
| ADMIN | 2026-08-01 00:00:00 | false | 1 | 1 |
| USUARIO | 2026-08-01 00:00:00 | false | 6 | 6 |
| USUARIO | 2026-08-01 00:00:00 | true | 2 | 2 |
| USUARIO | 2026-09-01 00:00:00 | false | 20.000 | 20.000 |
| **Total** | | | **20.009** | **20.009** |

Las verificaciones `EXCEPT` sobre las cuatro columnas agregadas (`rol`, `mes_alta`, `eliminado`, `cantidad_usuarios`) devolvieron **0 filas en ambas direcciones**. Por lo tanto, en esta copia y para esta consulta, la sustitución de nombres, apellidos, correos, celulares y contraseñas no alteró los conteos ni los grupos observados.

## Límite de privacidad

Los nombres, apellidos, correos, teléfonos, contraseñas, registros individuales y logs sin anonimizar de FoodStore no deben enviarse a un asistente de IA. `usuario_anon` conserva identificadores y fechas exactas para permitir esta prueba, de modo que no debe publicarse completa como si garantizara anonimato irreversible; se comparten solo el esquema, los datos sintéticos necesarios y los resultados agregados.
