/**
 * Gestión de roles configurables y sus permisos por acción (Fase 9).
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface RolConPermisos {
  id: string;
  nombre: string;
  codigo: string;
  descripcion: string | null;
  activo: boolean;
  permisos: string[];
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool no disponible.");
  return p;
}

export async function listRoles(schema: string, empresaId: string): Promise<RolConPermisos[]> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "roles");
  const tRP = quoteSchemaTable(schema, "rol_permisos");
  const client = await pool().connect();
  try {
    const roles = await client.query(`SELECT id, nombre, codigo, descripcion, activo FROM ${tR} WHERE empresa_id = $1::uuid ORDER BY nombre`, [empresaId]);
    const perms = await client.query(`SELECT rol_id, permiso FROM ${tRP} WHERE empresa_id = $1::uuid`, [empresaId]);
    const byRol = new Map<string, string[]>();
    for (const p of perms.rows) {
      const arr = byRol.get(p.rol_id) ?? [];
      arr.push(p.permiso);
      byRol.set(p.rol_id, arr);
    }
    return roles.rows.map((r) => ({ id: r.id, nombre: r.nombre, codigo: r.codigo, descripcion: r.descripcion, activo: r.activo, permisos: byRol.get(r.id) ?? [] }));
  } finally {
    client.release();
  }
}

export async function guardarRol(
  schema: string,
  empresaId: string,
  input: { id?: string; nombre: string; codigo: string; descripcion?: string | null; activo?: boolean; permisos: string[] },
): Promise<{ id: string }> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "roles");
  const tRP = quoteSchemaTable(schema, "rol_permisos");
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    let rolId = input.id ?? null;
    if (rolId) {
      await client.query(`UPDATE ${tR} SET nombre = $1, descripcion = $2, activo = $3, updated_at = now() WHERE id = $4::uuid AND empresa_id = $5::uuid`, [input.nombre, input.descripcion ?? null, input.activo !== false, rolId, empresaId]);
    } else {
      const r = await client.query(
        `INSERT INTO ${tR} (empresa_id, nombre, codigo, descripcion, activo) VALUES ($1::uuid, $2, $3, $4, $5)
         ON CONFLICT (empresa_id, codigo) DO UPDATE SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion, activo = EXCLUDED.activo, updated_at = now()
         RETURNING id`,
        [empresaId, input.nombre, input.codigo, input.descripcion ?? null, input.activo !== false],
      );
      rolId = r.rows[0].id as string;
    }
    await client.query(`DELETE FROM ${tRP} WHERE empresa_id = $1::uuid AND rol_id = $2::uuid`, [empresaId, rolId]);
    for (const permiso of input.permisos) {
      await client.query(`INSERT INTO ${tRP} (empresa_id, rol_id, permiso) VALUES ($1::uuid, $2::uuid, $3) ON CONFLICT (rol_id, permiso) DO NOTHING`, [empresaId, rolId, permiso]);
    }
    await client.query("COMMIT");
    return { id: rolId as string };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export async function eliminarRol(schema: string, empresaId: string, rolId: string): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "roles");
  const client = await pool().connect();
  try {
    await client.query(`DELETE FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid`, [rolId, empresaId]);
  } finally {
    client.release();
  }
}

export async function asignarRolUsuario(schema: string, empresaId: string, usuarioEmail: string, rolId: string, usuarioId?: string | null): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tUR = quoteSchemaTable(schema, "usuario_roles");
  const client = await pool().connect();
  try {
    await client.query(`INSERT INTO ${tUR} (empresa_id, usuario_email, usuario_id, rol_id) VALUES ($1::uuid, $2, $3::uuid, $4::uuid) ON CONFLICT (usuario_email, rol_id) DO NOTHING`, [empresaId, usuarioEmail, usuarioId ?? null, rolId]);
  } finally {
    client.release();
  }
}

export async function quitarRolUsuario(schema: string, empresaId: string, usuarioEmail: string, rolId: string): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tUR = quoteSchemaTable(schema, "usuario_roles");
  const client = await pool().connect();
  try {
    await client.query(`DELETE FROM ${tUR} WHERE empresa_id = $1::uuid AND usuario_email = $2 AND rol_id = $3::uuid`, [empresaId, usuarioEmail, rolId]);
  } finally {
    client.release();
  }
}

export async function listUsuarioRoles(schema: string, empresaId: string): Promise<Array<{ usuario_email: string; rol_id: string }>> {
  assertAllowedChatDataSchema(schema);
  const tUR = quoteSchemaTable(schema, "usuario_roles");
  const client = await pool().connect();
  try {
    const res = await client.query(`SELECT usuario_email, rol_id FROM ${tUR} WHERE empresa_id = $1::uuid`, [empresaId]);
    return res.rows as Array<{ usuario_email: string; rol_id: string }>;
  } finally {
    client.release();
  }
}
