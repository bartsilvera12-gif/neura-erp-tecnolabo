# Neura ERP — Tecnolabo

Instancia ERP dedicada de **Tecnolabo**, derivada del baseline aprobado de Neura ERP.

Modelo vigente: **1 cliente = 1 repo = 1 schema = 1 deploy**.

| Recurso | Valor |
| --- | --- |
| Repositorio | `bartsilvera12-gif/neura-erp-tecnolabo` |
| Branch productiva | `main` |
| Schema PostgreSQL | `tecnolabo` |
| Modo de instancia | `single_client` |
| Aplicación Coolify | `tecnolabo-erp` |
| Dominio | `tecnolabo.neura.com.py` |
| Supabase (público) | `https://api.neura.com.py` |

## Stack

Next.js (App Router) · React · Tailwind · Supabase self-hosted (PostgreSQL, GoTrue, PostgREST, Storage) · Coolify + Nixpacks.

## Desarrollo local

```bash
npm ci
npm run lint
npm run build
npm run dev
```

Copiá `.env.example` a `.env.local` y completá los valores desde el gestor de secretos autorizado.
**Nunca** commitees `.env*` con valores reales.

## Aislamiento de datos

Esta instancia opera exclusivamente sobre el schema `tecnolabo`:

- El schema se resuelve en `src/lib/supabase/schema.ts`. `NEXT_PUBLIC_APP_DB_SCHEMA` es la única
  variable que Next.js incrusta en el bundle del navegador; sin ella el cliente browser no conoce
  el schema y caería al valor por defecto.
- El valor por defecto es `tecnolabo`. **No** debe apuntar a `public`, `zentra_erp` ni al schema
  de otro cliente.
- El schema debe estar expuesto en PostgREST. Si el login entra y vuelve a salir, o aparece
  `PGRST106`/`406`, la causa habitual es que el schema no está expuesto.

Verificación REST:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "apikey: $ANON_KEY" -H "Accept-Profile: tecnolabo" "https://api.neura.com.py/rest/v1/"
```

## Base de datos

Las migraciones versionadas viven en `supabase/migrations/`. La provisión inicial del schema
`tecnolabo` está en `supabase/migrations/20260803120000_provision_schema_tecnolabo.sql`,
idempotente y reproducible.

## Branding

El nombre comercial, el logo y los datos fiscales se centralizan en
`src/lib/branding/cliente.ts`. El logo y los datos fiscales están **pendientes**: quedan vacíos
a propósito hasta recibir la información real de Tecnolabo. No se heredan los del ERP fuente.
