# Clean It — Recontactador Kommo con sync en vivo

Herramienta HTML + Supabase para trabajar la base histórica de Kommo / Google Sheets con turnos cancelados y leads perdidos.

Esta versión cambia el criterio operativo: **el Google Sheet funciona como fuente de datos base** y Supabase guarda la gestión comercial: estado de contacto, observaciones, check de servicio realizado, auditoría y permisos.

## Qué incluye

- Login con Supabase Auth.
- Base histórica filtrable por franquicia, servicio, estado, operador y servicio realizado.
- Ordenamiento por monto de mayor a menor o menor a mayor.
- Estado de contacto por fila:
  - Sin contactar
  - Recontactado
  - Cerrado
- Observaciones editables por fila.
- Check de servicio realizado.
- Link directo a Kommo.
- Link directo a WhatsApp si hay teléfono.
- Reportes por franquicia, servicio y estado.
- **Supabase Realtime**: si un usuario cambia una fila, los demás la ven actualizada sin refrescar.
- **Auto-sync desde Google Sheets / CSV público** cada 1, 2, 5 o 15 minutos.
- Sync seguro: cuando el Sheet cambia, actualiza los datos base, pero **no pisa**:
  - `estado_contacto`
  - `observaciones`
  - `servicio_realizado`
  - `assigned_to`

## Instalación nueva

1. Crear un proyecto en Supabase.
2. Ir a **SQL Editor**.
3. Ejecutar completo `schema.sql`.
4. Crear usuarios en **Authentication > Users**.
5. Abrir `index.html`.
6. Pegar:
   - Supabase Project URL
   - Supabase anon public key
7. Iniciar sesión.

## Actualización desde la versión anterior

Si ya habías instalado la versión anterior, no borres la tabla. Ejecutá igual el `schema.sql` completo. Está preparado con `if not exists` y agrega:

- columnas nuevas para sync;
- función `sync_cleanit_recontacts_from_sheet`;
- configuración de Realtime para `cleanit_recontacts`.

## Roles

| Rol | Permisos |
|---|---|
| `operador` | Ve y actualiza registros asignados. Recibe cambios en tiempo real. |
| `supervisora` | Ve todos, sincroniza desde Sheet, importa y actualiza estados/observaciones. |
| `admin` | Ve, sincroniza, importa, actualiza y elimina. |

Asignar supervisora:

```sql
update public.cleanit_profiles
set full_name = 'Nombre Supervisora', role = 'supervisora'
where email = 'supervisora@cleanit.com.ar';
```

Asignar admin:

```sql
update public.cleanit_profiles
set role = 'admin'
where email = 'admin@cleanit.com.ar';
```

## Configurar sync desde Google Sheets

La supervisora o admin debe entrar a la app y abrir **Configuración**.

Completar:

1. **URL del Google Sheet / CSV fuente**.
2. **Auto-sync desde Sheet**: cada 1, 2, 5 o 15 minutos.
3. **Sincronizar solo cancelados/perdidos**: recomendado `Sí`.
4. Tocar **Guardar sync y activar**.

También se puede usar **Sync ahora** desde la barra superior.

## URL correcta del Sheet

Para leer una pestaña específica del Google Sheet, conviene copiar la URL con `gid` de la pestaña real. Ejemplo:

```text
https://docs.google.com/spreadsheets/d/ID_DEL_SHEET/edit?gid=123456789
```

Si necesitás leer por nombre de pestaña, también podés usar formato CSV de Google Visualization:

```text
https://docs.google.com/spreadsheets/d/ID_DEL_SHEET/gviz/tq?tqx=out:csv&sheet=BD_TURNOS
```

Cambiar `BD_TURNOS` por la pestaña que corresponda, por ejemplo `BD_LEADS`.

## Importante sobre “tiempo real”

Hay dos capas:

1. **Tiempo real dentro de la app:** Supabase Realtime. Los cambios hechos por usuarios se reflejan en otros usuarios sin refrescar.
2. **Actualización desde Google Sheets:** se hace por auto-sync cada X minutos mientras una sesión admin/supervisora tenga la app abierta.

Para que el Sheet empuje cambios aun sin nadie con la app abierta, hace falta un puente server-side: Google Apps Script, Supabase Edge Function o un job externo. No conviene meter una `service_role key` en el HTML. Eso sería abrir la bóveda con moño azul.

## Columnas recomendadas en la base

La app intenta detectar columnas automáticamente. Funciona mejor si el Sheet/CSV tiene nombres similares a:

- `ID Kommo`
- `Link Kommo`
- `Fecha`
- `Cliente`
- `Teléfono`
- `Email`
- `Franquicia`
- `Servicio`
- `Monto`
- `Estado`
- `Observaciones`

También busca textos como `cancelado`, `cancelada`, `perdido`, `lead perdido`, `lost`, etc. para priorizar registros recuperables.

## Seguridad

- Usar la `anon public key` solo en el HTML.
- No usar la `service_role key` en el HTML.
- La función de sync solo permite ejecutar a usuarios con rol `admin` o `supervisora`.
- RLS sigue activo para proteger la lectura y escritura según rol.
