/**
 * Cuentas por pagar (Fase 2 — creación + listado).
 *
 * Una compra a crédito genera su obligación financiera (cuenta_por_pagar) al
 * registrarse, SIN aumentar inventario (eso ocurre al confirmar la recepción).
 * Idempotente: UNIQUE(empresa_id, compra_numero_control) evita CxP duplicadas
 * por reintento. La gestión de pagos parciales/historial se amplía en Fase 8.
 */
import type { PoolClient } from "pg";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface CrearCxpDesdeCompraParams {
  proveedorId: string | null;
  proveedorNombre: string | null;
  numeroControl: string;
  moneda: string;
  tipoCambio: number;
  total: number;
  plazoDias?: number | null;
  observacion?: string | null;
}

/**
 * Crea (idempotentemente) la cuenta por pagar de una compra a crédito dentro de
 * la transacción del caller. Devuelve el id (o null si ya existía).
 */
export async function crearCuentaPorPagarDesdeCompraTx(
  client: PoolClient,
  schema: string,
  empresaId: string,
  params: CrearCxpDesdeCompraParams,
): Promise<{ cuentaId: string | null; yaExistia: boolean }> {
  assertAllowedChatDataSchema(schema);
  const t = quoteSchemaTable(schema, "cuentas_por_pagar");
  const plazo = params.plazoDias != null && params.plazoDias > 0 ? String(params.plazoDias) : null;

  const res = await client.query(
    `INSERT INTO ${t} (
       empresa_id, proveedor_id, proveedor_nombre, compra_numero_control,
       moneda, tipo_cambio, total, saldo, fecha_emision, fecha_vencimiento, estado, observacion
     ) VALUES (
       $1::uuid, $2::uuid, $3, $4,
       $5, $6::numeric, $7::numeric, $7::numeric, CURRENT_DATE,
       CASE WHEN $8::text IS NULL THEN NULL ELSE (CURRENT_DATE + ($8 || ' days')::interval)::date END,
       'pendiente', $9
     )
     ON CONFLICT (empresa_id, compra_numero_control) WHERE compra_numero_control IS NOT NULL
       DO NOTHING
     RETURNING id`,
    [
      empresaId,
      params.proveedorId ?? null,
      params.proveedorNombre ?? null,
      params.numeroControl,
      params.moneda || "PYG",
      params.tipoCambio || 1,
      params.total || 0,
      plazo,
      params.observacion ?? null,
    ],
  );
  if (res.rowCount === 0) return { cuentaId: null, yaExistia: true };
  return { cuentaId: res.rows[0].id as string, yaExistia: false };
}

export interface CuentaPorPagarRow {
  id: string;
  proveedor_id: string | null;
  proveedor_nombre: string | null;
  compra_numero_control: string | null;
  moneda: string;
  total: number;
  saldo: number;
  fecha_emision: string;
  fecha_vencimiento: string | null;
  estado: string;
  dias_atraso: number;
}

/** Lista las cuentas por pagar con días de atraso calculados. */
export async function listCuentasPorPagar(
  schema: string,
  empresaId: string,
  opts: { estado?: string; proveedorId?: string } = {},
): Promise<CuentaPorPagarRow[]> {
  assertAllowedChatDataSchema(schema);
  const pool = getChatPostgresPool();
  if (!pool) throw new Error("Pool no disponible.");
  const t = quoteSchemaTable(schema, "cuentas_por_pagar");
  const where: string[] = ["empresa_id = $1::uuid"];
  const vals: unknown[] = [empresaId];
  if (opts.estado) {
    vals.push(opts.estado);
    where.push(`estado = $${vals.length}`);
  }
  if (opts.proveedorId) {
    vals.push(opts.proveedorId);
    where.push(`proveedor_id = $${vals.length}::uuid`);
  }
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT id, proveedor_id, proveedor_nombre, compra_numero_control, moneda,
              total, saldo, fecha_emision, fecha_vencimiento, estado,
              GREATEST(0, CASE WHEN fecha_vencimiento IS NULL OR saldo <= 0 THEN 0
                              ELSE (CURRENT_DATE - fecha_vencimiento) END)::int AS dias_atraso
         FROM ${t}
        WHERE ${where.join(" AND ")}
        ORDER BY (fecha_vencimiento IS NULL), fecha_vencimiento ASC, created_at DESC`,
      vals,
    );
    return res.rows as CuentaPorPagarRow[];
  } finally {
    client.release();
  }
}
