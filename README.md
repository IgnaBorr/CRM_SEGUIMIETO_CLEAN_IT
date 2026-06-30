# Clean It — Agenda Comercial / Mini CRM Supabase v2

App HTML operativa conectada a Supabase para seguimiento comercial interno de Clean It.

Esta versión agrega dos bloques importantes:

1. Cada seguimiento tiene campos específicos para:
   - Link de Kommo
   - Tipo de servicio
   - Descripción del servicio / oportunidad
   - Monto

2. La supervisora puede ingresar y ver los seguimientos individuales de cada operador.

## Archivos

- `index.html`: aplicación completa en un solo archivo.
- `schema.sql`: base Supabase, perfiles, roles, políticas RLS e índices.
- `assets/cleanit-logo.png`: logo aplicado a la interfaz.

## Instalación

### 1. Crear proyecto en Supabase

Crear un proyecto en Supabase y copiar:

- Project URL
- anon public key

No usar la `service_role key` en el HTML.

### 2. Ejecutar la base

En Supabase > SQL Editor, pegar y ejecutar completo el archivo:

```sql
schema.sql
```

El script es reejecutable y no borra datos existentes. Si ya habías instalado la versión anterior, agrega los nuevos campos sin eliminar la información cargada.

Tablas principales:

```sql
public.cleanit_commercial_agenda
public.cleanit_profiles
```

## Roles

La app maneja tres roles:

| Rol | Acceso |
|---|---|
| `operador` | Ve, crea y edita solo sus propios seguimientos. |
| `supervisora` | Ve los seguimientos de todos los operadores y puede filtrar por operador. No edita seguimientos ajenos. |
| `admin` | Ve todo y puede editar/eliminar todos los seguimientos. |

## Crear usuarios

Primero crear usuarios desde:

Supabase > Authentication > Users

Después ejecutar en SQL Editor algo así:

```sql
update public.cleanit_profiles
set full_name = 'Nombre Operador', role = 'operador'
where email = 'operador@cleanit.com.ar';

update public.cleanit_profiles
set full_name = 'Nombre Supervisora', role = 'supervisora'
where email = 'supervisora@cleanit.com.ar';

update public.cleanit_profiles
set full_name = 'Administrador', role = 'admin'
where email = 'admin@cleanit.com.ar';
```

Si un usuario ya existía antes de correr este schema, el script hace un backfill automático en `cleanit_profiles`.

## Conectar el HTML

Tenés dos opciones.

### Opción rápida

Abrir `index.html` en el navegador. La app pide:

- Project URL
- anon public key

Los datos quedan guardados en `localStorage`.

### Opción producción

Editar `index.html` y reemplazar:

```js
const DEFAULT_SUPABASE_URL = "https://TU-PROYECTO.supabase.co";
const DEFAULT_SUPABASE_ANON_KEY = "TU-ANON-KEY";
```

por los datos reales del proyecto.

## Funcionalidades incluidas

- Login con Supabase Auth.
- Diseño Clean It con tipografía Nunito.
- Dashboard comercial.
- Agenda de seguimientos.
- Calendario mensual.
- Pipeline de oportunidades.
- Vista por operador para supervisora/admin.
- Alta, edición y eliminación de seguimientos.
- Campos de Kommo, servicio, descripción y monto.
- Cambio rápido de etapa.
- Marcar tareas como completadas.
- Botón directo a WhatsApp si hay teléfono.
- Link directo a Kommo si está cargado.
- Reportes básicos por etapa, operador, pipeline y cierres.

## Seguridad

La seguridad está en Row Level Security:

- Operador: solo ve sus registros.
- Supervisora: ve todos los registros, pero no edita registros ajenos.
- Admin: ve y edita todo.

Esto evita el error típico de dejar toda la base expuesta desde un HTML público. La anon key puede estar en frontend; la service_role key no.

## Nota operativa

Si Clean It va a usar esto como herramienta real de gestión comercial, el próximo salto recomendable sería separar la base en:

- `clientes`
- `oportunidades`
- `seguimientos`
- `actividades`
- `usuarios / roles`

Para esta etapa, una sola tabla comercial mantiene bajo el costo de implementación y permite salir a producción más rápido.
