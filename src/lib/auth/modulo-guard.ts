/**
 * Gate de MÓDULO para el backend.
 *
 * El acceso por módulo se aplicaba solo en el cliente (Sidebar + AuthGuard), así
 * que las APIs respondían igual aunque el módulo estuviera denegado: bastaba
 * llamar al endpoint a mano. Esto cierra esa puerta reusando exactamente la
 * misma fuente de verdad que la UI (`empresa_modulos` ∩ `usuario_modulos`), sin
 * crear un segundo sistema de permisos.
 *
 * Reglas, iguales a las del resolver de la UI:
 *  - admin / administrador / super_admin → pasa siempre;
 *  - usuario SIN filas en `usuario_modulos` → comportamiento legado (pasa), para
 *    no romper cuentas existentes que nunca fueron acotadas;
 *  - usuario CON módulos asignados → se exige el slug puntual.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export class ModuloError extends Error {
  status = 403;
  slug: string;
  constructor(slug: string) {
    super("No tenés acceso al módulo requerido.");
    this.name = "ModuloError";
    this.slug = slug;
  }
}

function esAdmin(rol?: string | null): boolean {
  const r = (rol ?? "").trim().toLowerCase();
  return r === "super_admin" || r === "admin" || r === "administrador";
}

/**
 * Slugs efectivos del usuario, o `null` si aplica el comportamiento legado
 * (admin, sin pool, o usuario sin módulos asignados) = todos.
 */
export async function resolveModulosUsuario(
  schema: string,
  empresaId: string,
  authUserId: string | null | undefined,
  rolConocido?: string | null,
): Promise<Set<string> | null> {
  assertAllowedChatDataSchema(schema);
  if (esAdmin(rolConocido)) return null;

  const pool = getChatPostgresPool();
  if (!pool) return null;

  const tU = quoteSchemaTable(schema, "usuarios");
  const tUM = quoteSchemaTable(schema, "usuario_modulos");
  const tM = quoteSchemaTable(schema, "modulos");
  const tEM = quoteSchemaTable(schema, "empresa_modulos");

  const client = await pool.connect();
  try {
    const u = await client.query(
      `SELECT id, rol FROM ${tU} WHERE empresa_id = $1::uuid AND auth_user_id = $2::uuid LIMIT 1`,
      [empresaId, authUserId ?? null],
    );
    // Sin ficha en el ERP no se puede resolver nada: se cae al modo legado para
    // no romper flujos de cuentas de servicio.
    if ((u.rowCount ?? 0) === 0) return null;
    if (esAdmin(u.rows[0].rol)) return null;

    const usuarioId = u.rows[0].id as string;
    const mods = await client.query(
      `SELECT m.slug
         FROM ${tUM} um
         JOIN ${tM} m  ON m.id = um.modulo_id
         JOIN ${tEM} em ON em.modulo_id = m.id AND em.empresa_id = $2::uuid AND em.activo
        WHERE um.usuario_id = $1::uuid`,
      [usuarioId, empresaId],
    );
    if ((mods.rowCount ?? 0) === 0) return null; // sin módulos → legado

    return new Set(mods.rows.map((r) => String(r.slug)));
  } finally {
    client.release();
  }
}

/** Lanza ModuloError (403) si el usuario está acotado y le falta el módulo. */
export async function assertModulo(
  schema: string,
  empresaId: string,
  authUserId: string | null | undefined,
  slug: string,
  rolConocido?: string | null,
): Promise<void> {
  const slugs = await resolveModulosUsuario(schema, empresaId, authUserId, rolConocido);
  if (slugs === null) return;
  if (!slugs.has(slug)) throw new ModuloError(slug);
}
