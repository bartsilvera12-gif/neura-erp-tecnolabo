/**
 * Pagos a proveedor sobre cuentas por pagar (Fase 8).
 *
 * Transaccional e idempotente: FOR UPDATE sobre la cuenta por pagar; el pago
 * descuenta el saldo y recalcula el estado (pendiente/parcial/pagado). La
 * reversión (anulación de un pago) devuelve el saldo sin borrar el historial.
 * Reutiliza la tabla `pagos_proveedor` creada en F2.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

export class PagoProveedorError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.name = "PagoProveedorError";
    this.status = status;
  }
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

export interface RegistrarPagoProveedorInput {
  cuenta_por_pagar_id: string;
  monto: number;
  metodo_pago?: string;
  referencia?: string | null;
  fecha_pago?: string | null;
  observacion?: string | null;
  comprobante_url?: string | null;
  comprobante_storage_path?: string | null;
  comprobante_nombre?: string | null;
  comprobante_mime_type?: string | null;
  usuario_id?: string | null;
  usuario_nombre?: string | null;
  usuario_email?: string | null;
  idempotency_key?: string | null;
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new PagoProveedorError("Pool no disponible.", 500);
  return p;
}

export async function registrarPagoProveedor(
  schema: string,
  empresaId: string,
  input: RegistrarPagoProveedorInput,
): Promise<{ pago_id: string; saldo_nuevo: number; estado: string; ya_existia: boolean }> {
  assertAllowedChatDataSchema(schema);
  const monto = round2(Number(input.monto) || 0);
  if (!(monto > 0)) throw new PagoProveedorError("El monto del pago debe ser mayor a cero.");
  if (!input.cuenta_por_pagar_id) throw new PagoProveedorError("Falta la cuenta por pagar.");

  const tCxp = quoteSchemaTable(schema, "cuentas_por_pagar");
  const tPag = quoteSchemaTable(schema, "pagos_proveedor");
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const cq = await client.query(`SELECT id, proveedor_id, total, saldo, estado FROM ${tCxp} WHERE empresa_id = $1::uuid AND id = $2::uuid FOR UPDATE`, [empresaId, input.cuenta_por_pagar_id]);
    if (cq.rowCount === 0) throw new PagoProveedorError("Cuenta por pagar no encontrada.", 404);
    const cxp = cq.rows[0];

    if (input.idempotency_key) {
      const prev = await client.query(`SELECT id FROM ${tPag} WHERE cuenta_por_pagar_id = $1::uuid AND referencia = $2 AND anulado_at IS NULL`, [cxp.id, `idem:${input.idempotency_key}`]);
      if ((prev.rowCount ?? 0) > 0) {
        await client.query("COMMIT");
        return { pago_id: prev.rows[0].id, saldo_nuevo: round2(Number(cxp.saldo) || 0), estado: cxp.estado, ya_existia: true };
      }
    }

    if (cxp.estado === "anulado") throw new PagoProveedorError("La cuenta está anulada.", 409);
    if (cxp.estado === "pagado") throw new PagoProveedorError("La cuenta ya está pagada.", 409);

    const saldoActual = round2(Number(cxp.saldo) || 0);
    const total = round2(Number(cxp.total) || 0);
    if (monto > saldoActual + 0.001) throw new PagoProveedorError(`El monto (${monto}) supera el saldo pendiente (${saldoActual}).`);

    const fechaPago = typeof input.fecha_pago === "string" && input.fecha_pago.trim() ? input.fecha_pago : new Date().toISOString().slice(0, 10);
    const referencia = input.idempotency_key ? `idem:${input.idempotency_key}` : input.referencia?.trim() || null;

    const ins = await client.query(
      `INSERT INTO ${tPag} (
         empresa_id, cuenta_por_pagar_id, proveedor_id, fecha_pago, monto, metodo_pago, referencia,
         comprobante_url, comprobante_storage_path, comprobante_nombre, comprobante_mime_type,
         usuario_id, usuario_nombre, observacion
       ) VALUES (
         $1::uuid, $2::uuid, $3::uuid, $4::date, $5::numeric, $6, $7,
         $8, $9, $10, $11,
         $12::uuid, $13, $14
       ) RETURNING id`,
      [empresaId, cxp.id, cxp.proveedor_id ?? null, fechaPago, monto, input.metodo_pago || "efectivo", referencia,
       input.comprobante_url ?? null, input.comprobante_storage_path ?? null, input.comprobante_nombre ?? null, input.comprobante_mime_type ?? null,
       input.usuario_id ?? null, input.usuario_nombre ?? null, input.observacion ?? null],
    );
    const pagoId = ins.rows[0].id as string;

    const saldoNuevo = round2(Math.max(0, saldoActual - monto));
    const estadoNuevo = saldoNuevo <= 0.001 ? "pagado" : saldoNuevo < total ? "parcial" : "pendiente";
    await client.query(`UPDATE ${tCxp} SET saldo = $1::numeric, estado = $2, updated_at = now() WHERE empresa_id = $3::uuid AND id = $4::uuid`, [saldoNuevo, estadoNuevo, empresaId, cxp.id]);

    await registrarAuditoriaTx(client, schema, {
      empresaId, entidad: "pago_proveedor", entidadId: pagoId, accion: "registrar", origen: "api/cuentas-por-pagar",
      usuarioId: input.usuario_id ?? null, usuarioEmail: input.usuario_email ?? null, usuarioNombre: input.usuario_nombre ?? null,
      detalle: { cuenta_por_pagar_id: cxp.id, monto, saldo_nuevo: saldoNuevo, estado: estadoNuevo },
    });

    await client.query("COMMIT");
    return { pago_id: pagoId, saldo_nuevo: saldoNuevo, estado: estadoNuevo, ya_existia: false };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    if (e instanceof PagoProveedorError) throw e;
    throw new PagoProveedorError(e instanceof Error ? e.message : "Error al registrar el pago.", 500);
  } finally {
    client.release();
  }
}

/** Reversión controlada: anula un pago y devuelve el saldo (sin borrar historial). */
export async function anularPagoProveedor(schema: string, empresaId: string, pagoId: string, usuario: { id?: string | null; nombre?: string | null; email?: string | null }, motivo: string): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tCxp = quoteSchemaTable(schema, "cuentas_por_pagar");
  const tPag = quoteSchemaTable(schema, "pagos_proveedor");
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const pq = await client.query(`SELECT id, cuenta_por_pagar_id, monto, anulado_at FROM ${tPag} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [pagoId, empresaId]);
    if (pq.rowCount === 0) throw new PagoProveedorError("Pago no encontrado.", 404);
    const pago = pq.rows[0];
    if (pago.anulado_at) throw new PagoProveedorError("El pago ya está anulado.", 409);

    const cq = await client.query(`SELECT id, total, saldo FROM ${tCxp} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [pago.cuenta_por_pagar_id, empresaId]);
    if (cq.rowCount === 0) throw new PagoProveedorError("Cuenta por pagar no encontrada.", 404);
    const cxp = cq.rows[0];
    const saldoNuevo = round2(Math.min(Number(cxp.total) || 0, (Number(cxp.saldo) || 0) + (Number(pago.monto) || 0)));
    const total = round2(Number(cxp.total) || 0);
    const estadoNuevo = saldoNuevo <= 0.001 ? "pagado" : saldoNuevo < total ? "parcial" : "pendiente";

    await client.query(`UPDATE ${tPag} SET anulado_at = now(), anulado_por = $1::uuid, anulado_motivo = $2 WHERE id = $3::uuid`, [usuario.id ?? null, motivo, pagoId]);
    await client.query(`UPDATE ${tCxp} SET saldo = $1::numeric, estado = $2, updated_at = now() WHERE id = $3::uuid`, [saldoNuevo, estadoNuevo, cxp.id]);

    await registrarAuditoriaTx(client, schema, {
      empresaId, entidad: "pago_proveedor", entidadId: pagoId, accion: "anular", origen: "api/cuentas-por-pagar",
      usuarioId: usuario.id ?? null, usuarioEmail: usuario.email ?? null, usuarioNombre: usuario.nombre ?? null,
      detalle: { cuenta_por_pagar_id: cxp.id, saldo_nuevo: saldoNuevo, motivo },
    });
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    if (e instanceof PagoProveedorError) throw e;
    throw new PagoProveedorError(e instanceof Error ? e.message : "Error al anular el pago.", 500);
  } finally {
    client.release();
  }
}

export async function listPagosDeCuenta(schema: string, empresaId: string, cuentaId: string) {
  assertAllowedChatDataSchema(schema);
  const tPag = quoteSchemaTable(schema, "pagos_proveedor");
  const client = await pool().connect();
  try {
    const res = await client.query(`SELECT id, fecha_pago, monto, metodo_pago, referencia, observacion, anulado_at FROM ${tPag} WHERE empresa_id = $1::uuid AND cuenta_por_pagar_id = $2::uuid ORDER BY created_at DESC`, [empresaId, cuentaId]);
    return res.rows;
  } finally {
    client.release();
  }
}
