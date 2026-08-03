/**
 * Permisos por acción (Fase 9).
 *
 * Capa opcional y retrocompatible sobre el gating por módulo existente:
 *  - super_admin / admin de empresa → todos los permisos.
 *  - Usuario SIN roles asignados → comportamiento legado (permitido) para no
 *    romper flujos productivos.
 *  - Usuario CON roles → se exige el permiso puntual; si no lo tiene, se deniega
 *    (403), incluyendo en el backend (test 17 del alcance).
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export const PERMISOS = [
  "crear",
  "editar",
  "aprobar",
  "confirmar_recepcion",
  "confirmar_salida",
  "confirmar_remision",
  "anular",
  "cobrar",
  "pagar",
  "exportar",
  "ver_costos",
  "ver_margenes",
] as const;
export type Permiso = (typeof PERMISOS)[number];

export const PERMISO_LABEL: Record<Permiso, string> = {
  crear: "Crear",
  editar: "Editar",
  aprobar: "Aprobar",
  confirmar_recepcion: "Confirmar recepción",
  confirmar_salida: "Confirmar salida",
  confirmar_remision: "Confirmar remisión",
  anular: "Anular",
  cobrar: "Cobrar",
  pagar: "Pagar",
  exportar: "Exportar",
  ver_costos: "Ver costos",
  ver_margenes: "Ver márgenes",
};

export class PermisoError extends Error {
  status = 403;
  permiso: string;
  constructor(permiso: string) {
    super(`No tenés permiso para: ${PERMISO_LABEL[permiso as Permiso] ?? permiso}.`);
    this.name = "PermisoError";
    this.permiso = permiso;
  }
}

function esAdmin(rol?: string | null): boolean {
  const r = (rol ?? "").trim().toLowerCase();
  return r === "super_admin" || r === "admin" || r === "administrador";
}

/**
 * Devuelve el conjunto de permisos del usuario, o `null` si aplica el
 * comportamiento legado (admin, o usuario sin roles asignados) = todos.
 */
export async function resolvePermisosUsuario(
  schema: string,
  empresaId: string,
  email: string | null | undefined,
  rolConocido?: string | null,
): Promise<Set<string> | null> {
  assertAllowedChatDataSchema(schema);
  if (esAdmin(rolConocido)) return null;
  const pool = getChatPostgresPool();
  if (!pool) return null; // sin pool no bloqueamos (legacy)
  const tU = quoteSchemaTable(schema, "usuarios");
  const tUR = quoteSchemaTable(schema, "usuario_roles");
  const tRP = quoteSchemaTable(schema, "rol_permisos");
  const client = await pool.connect();
  try {
    if (!rolConocido && email) {
      const u = await client.query(`SELECT rol FROM ${tU} WHERE empresa_id = $1::uuid AND lower(email) = lower($2) LIMIT 1`, [empresaId, email]);
      if ((u.rowCount ?? 0) > 0 && esAdmin(u.rows[0].rol)) return null;
    }
    const roles = await client.query(`SELECT rol_id FROM ${tUR} WHERE empresa_id = $1::uuid AND lower(usuario_email) = lower($2)`, [empresaId, email ?? ""]);
    if ((roles.rowCount ?? 0) === 0) return null; // sin roles → legacy permitido
    const rolIds = roles.rows.map((r) => r.rol_id as string);
    const perms = await client.query(
      `SELECT permiso FROM ${tRP} WHERE empresa_id = $1::uuid AND rol_id = ANY($2::uuid[])`,
      [empresaId, rolIds],
    );
    return new Set(perms.rows.map((r) => r.permiso as string));
  } finally {
    client.release();
  }
}

/** Lanza PermisoError (403) si el usuario tiene roles y le falta el permiso. */
export async function assertPermiso(
  schema: string,
  empresaId: string,
  email: string | null | undefined,
  permiso: Permiso,
  rolConocido?: string | null,
): Promise<void> {
  const perms = await resolvePermisosUsuario(schema, empresaId, email, rolConocido);
  if (perms === null) return; // legacy / admin → permitido
  if (!perms.has(permiso)) throw new PermisoError(permiso);
}
