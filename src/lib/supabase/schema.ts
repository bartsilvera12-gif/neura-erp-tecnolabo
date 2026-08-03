import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Instancia dedicada monocliente (Tecnolabo).
 * Schema único Postgres para catálogo + datos operativos.
 *
 * Resolución en orden:
 *  1. NEXT_PUBLIC_APP_DB_SCHEMA — la única que Next.js incrusta en el bundle del
 *     navegador. Sin ella el cliente browser no conoce el schema y cae al valor por
 *     defecto, que es exactamente cómo una instancia termina leyendo datos de otro
 *     cliente.
 *  2. APP_DB_SCHEMA / NEURA_CLIENT_SCHEMA — sólo resuelven en servidor.
 *  3. "tecnolabo" — schema propio de esta instancia. El fallback nunca debe apuntar
 *     al schema de otro cliente ni a `public`/`zentra_erp`.
 *
 * Los accesos a process.env se escriben literalmente a propósito: Next.js sustituye
 * estáticamente `process.env.NEXT_PUBLIC_*` y no resuelve accesos dinámicos.
 */
const SCHEMA_PUBLICO = process.env.NEXT_PUBLIC_APP_DB_SCHEMA?.trim();
const SCHEMA_SERVIDOR =
  typeof process !== "undefined"
    ? process.env.APP_DB_SCHEMA?.trim() || process.env.NEURA_CLIENT_SCHEMA?.trim()
    : undefined;

export const NEURA_CLIENT_SCHEMA: string = SCHEMA_PUBLICO || SCHEMA_SERVIDOR || "tecnolabo";

/**
 * Schema Postgres principal de la app.
 * En instancia dedicada equivale a NEURA_CLIENT_SCHEMA.
 * Requiere en Supabase: Settings → API → "Exposed schemas" incluir este schema.
 */
export const SUPABASE_APP_SCHEMA: string = NEURA_CLIENT_SCHEMA;

/**
 * Resolución de schema operativo por empresa.
 * En instancia dedicada monocliente siempre devuelve el schema único; el argumento se ignora.
 * Se mantiene la firma para compatibilidad con callers existentes.
 */
export function resolveEmpresaDataSchema(_dataSchema?: string | null): string {
  return NEURA_CLIENT_SCHEMA;
}

/**
 * Cliente Supabase con cualquier esquema PostgREST.
 * Con @supabase/supabase-js ≥2.99 los genéricos de `SupabaseClient` son varios y condicionales;
 * acotar alguno a `string` o `"public"` rompe la asignación entre instancias (p. ej. Vercel TS).
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AppSupabaseClient = SupabaseClient<any, any, any, any, any>;

export const supabaseDbSchemaOption = {
  db: { schema: SUPABASE_APP_SCHEMA },
} as const;

/** Cliente service role estándar (API routes, webhooks, jobs). */
export const supabaseServiceRoleClientOptions = {
  auth: { autoRefreshToken: false, persistSession: false },
  ...supabaseDbSchemaOption,
} as const;
