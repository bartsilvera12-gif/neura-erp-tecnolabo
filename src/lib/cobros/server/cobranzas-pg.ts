/**
 * Cobranzas (Fase 7): tramos de aging configurables, promesas de pago y
 * gestiones de cobranza. No hardcodea los tramos: si la empresa no configuró
 * ninguno, se usan defaults en memoria (no se persisten hasta que la empresa
 * los edite).
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface Tramo {
  id?: string;
  nombre: string;
  dias_desde: number | null;
  dias_hasta: number | null;
  orden: number;
  color: string | null;
  activo: boolean;
}

export const TRAMOS_DEFAULT: Tramo[] = [
  { nombre: "Próximos a vencer", dias_desde: -7, dias_hasta: 0, orden: 1, color: "#0ea5e9", activo: true },
  { nombre: "Vencido 1-30", dias_desde: 1, dias_hasta: 30, orden: 2, color: "#f59e0b", activo: true },
  { nombre: "Vencido 31-60", dias_desde: 31, dias_hasta: 60, orden: 3, color: "#f97316", activo: true },
  { nombre: "Vencido +60", dias_desde: 61, dias_hasta: null, orden: 4, color: "#dc2626", activo: true },
];

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool no disponible.");
  return p;
}

/** Tramos configurados de la empresa; si no hay, devuelve los defaults. */
export async function getTramos(schema: string, empresaId: string): Promise<Tramo[]> {
  assertAllowedChatDataSchema(schema);
  const t = quoteSchemaTable(schema, "aging_tramos");
  const client = await pool().connect();
  try {
    const res = await client.query(
      `SELECT id, nombre, dias_desde, dias_hasta, orden, color, activo FROM ${t} WHERE empresa_id = $1::uuid AND activo = true ORDER BY orden`,
      [empresaId],
    );
    if (res.rowCount === 0) return TRAMOS_DEFAULT;
    return res.rows as Tramo[];
  } finally {
    client.release();
  }
}

/** Reemplaza la configuración de tramos de la empresa (transaccional). */
export async function guardarTramos(schema: string, empresaId: string, tramos: Tramo[]): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const t = quoteSchemaTable(schema, "aging_tramos");
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    await client.query(`DELETE FROM ${t} WHERE empresa_id = $1::uuid`, [empresaId]);
    let orden = 0;
    for (const tr of tramos) {
      orden += 1;
      await client.query(
        `INSERT INTO ${t} (empresa_id, nombre, dias_desde, dias_hasta, orden, color, activo)
           VALUES ($1::uuid, $2, $3, $4, $5, $6, $7)`,
        [empresaId, tr.nombre, tr.dias_desde, tr.dias_hasta, orden, tr.color ?? null, tr.activo !== false],
      );
    }
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

/** Clasifica un atraso (días) en el nombre del tramo correspondiente. */
export function clasificarTramo(diasAtraso: number, tramos: Tramo[]): string {
  for (const tr of tramos) {
    const desde = tr.dias_desde ?? -Infinity;
    const hasta = tr.dias_hasta ?? Infinity;
    if (diasAtraso >= desde && diasAtraso <= hasta) return tr.nombre;
  }
  return "Sin clasificar";
}

// ── Promesas de pago ─────────────────────────────────────────────────────────
export interface PromesaInput {
  cliente_id: string;
  cuenta_por_cobrar_id?: string | null;
  fecha_promesa: string;
  monto: number;
  observacion?: string | null;
  responsable_id?: string | null;
  responsable_nombre?: string | null;
  recordatorio_at?: string | null;
  created_by?: string | null;
}

export async function crearPromesa(schema: string, empresaId: string, input: PromesaInput): Promise<{ id: string }> {
  assertAllowedChatDataSchema(schema);
  const t = quoteSchemaTable(schema, "promesas_pago");
  const client = await pool().connect();
  try {
    const res = await client.query(
      `INSERT INTO ${t} (empresa_id, cliente_id, cuenta_por_cobrar_id, fecha_promesa, monto, observacion, responsable_id, responsable_nombre, recordatorio_at, created_by)
         VALUES ($1::uuid, $2::uuid, $3::uuid, $4::date, $5::numeric, $6, $7::uuid, $8, $9::timestamptz, $10::uuid) RETURNING id`,
      [empresaId, input.cliente_id, input.cuenta_por_cobrar_id ?? null, input.fecha_promesa, Number(input.monto) || 0, input.observacion ?? null, input.responsable_id ?? null, input.responsable_nombre ?? null, input.recordatorio_at ?? null, input.created_by ?? null],
    );
    return { id: res.rows[0].id as string };
  } finally {
    client.release();
  }
}

export async function actualizarEstadoPromesa(schema: string, empresaId: string, id: string, estado: string): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const valido = ["pendiente", "cumplida", "incumplida", "anulada"].includes(estado) ? estado : "pendiente";
  const t = quoteSchemaTable(schema, "promesas_pago");
  const client = await pool().connect();
  try {
    await client.query(`UPDATE ${t} SET estado = $1, updated_at = now() WHERE id = $2::uuid AND empresa_id = $3::uuid`, [valido, id, empresaId]);
  } finally {
    client.release();
  }
}

export async function listPromesas(schema: string, empresaId: string, clienteId?: string) {
  assertAllowedChatDataSchema(schema);
  const t = quoteSchemaTable(schema, "promesas_pago");
  const where = ["empresa_id = $1::uuid"];
  const vals: unknown[] = [empresaId];
  if (clienteId) {
    vals.push(clienteId);
    where.push(`cliente_id = $${vals.length}::uuid`);
  }
  const client = await pool().connect();
  try {
    const res = await client.query(`SELECT * FROM ${t} WHERE ${where.join(" AND ")} ORDER BY fecha_promesa DESC`, vals);
    return res.rows;
  } finally {
    client.release();
  }
}

// ── Gestiones de cobranza ────────────────────────────────────────────────────
export interface GestionInput {
  cliente_id: string;
  cuenta_por_cobrar_id?: string | null;
  tipo: string;
  resultado?: string | null;
  observacion?: string | null;
  usuario_id?: string | null;
  usuario_nombre?: string | null;
}

export async function crearGestion(schema: string, empresaId: string, input: GestionInput): Promise<{ id: string }> {
  assertAllowedChatDataSchema(schema);
  const tipo = ["llamada", "whatsapp", "correo", "visita", "nota", "otro"].includes(input.tipo) ? input.tipo : "nota";
  const t = quoteSchemaTable(schema, "gestiones_cobranza");
  const client = await pool().connect();
  try {
    const res = await client.query(
      `INSERT INTO ${t} (empresa_id, cliente_id, cuenta_por_cobrar_id, tipo, resultado, observacion, usuario_id, usuario_nombre)
         VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6, $7::uuid, $8) RETURNING id`,
      [empresaId, input.cliente_id, input.cuenta_por_cobrar_id ?? null, tipo, input.resultado ?? null, input.observacion ?? null, input.usuario_id ?? null, input.usuario_nombre ?? null],
    );
    return { id: res.rows[0].id as string };
  } finally {
    client.release();
  }
}

export async function listGestiones(schema: string, empresaId: string, clienteId?: string) {
  assertAllowedChatDataSchema(schema);
  const t = quoteSchemaTable(schema, "gestiones_cobranza");
  const where = ["empresa_id = $1::uuid"];
  const vals: unknown[] = [empresaId];
  if (clienteId) {
    vals.push(clienteId);
    where.push(`cliente_id = $${vals.length}::uuid`);
  }
  const client = await pool().connect();
  try {
    const res = await client.query(`SELECT * FROM ${t} WHERE ${where.join(" AND ")} ORDER BY fecha DESC LIMIT 200`, vals);
    return res.rows;
  } finally {
    client.release();
  }
}
