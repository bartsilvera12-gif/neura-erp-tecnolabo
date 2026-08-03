/**
 * Cobro transaccional e idempotente (Fase 7).
 *
 * Reemplaza el camino no-atómico de `registrarCobro` (PostgREST insert+update).
 * - Una sola transacción con SELECT ... FOR UPDATE sobre la cuenta por cobrar.
 * - `idempotency_key` evita doble aplicación por doble clic / reintento HTTP.
 * - Si la CxC proviene de una factura (factura_id), sincroniza factura.saldo/estado.
 * - Registra auditoría.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

export type MetodoPagoCobro = "efectivo" | "transferencia" | "tarjeta" | "otro";

export class CobroError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.name = "CobroError";
    this.status = status;
  }
}

export interface RegistrarCobroPgInput {
  cuenta_por_cobrar_id: string;
  monto: number;
  metodo_pago: MetodoPagoCobro;
  entidad_bancaria_id?: string | null;
  entidad_nombre_snapshot?: string | null;
  referencia?: string | null;
  titular?: string | null;
  observaciones?: string | null;
  fecha_pago?: string | null;
  usuario_id?: string | null;
  usuario_nombre?: string | null;
  usuario_email?: string | null;
  idempotency_key?: string | null;
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}
function metodoValido(m: unknown): MetodoPagoCobro {
  return m === "transferencia" || m === "tarjeta" || m === "otro" ? m : "efectivo";
}

export async function registrarCobroPg(
  schema: string,
  empresaId: string,
  input: RegistrarCobroPgInput,
): Promise<{ cobro_id: string; saldo_nuevo: number; estado: string; ya_existia: boolean }> {
  assertAllowedChatDataSchema(schema);
  const monto = round2(Number(input.monto) || 0);
  if (!(monto > 0)) throw new CobroError("El monto del cobro debe ser mayor a cero.");
  if (!input.cuenta_por_cobrar_id) throw new CobroError("Falta la cuenta por cobrar.");

  const pool = getChatPostgresPool();
  if (!pool) throw new CobroError("Pool no disponible.", 500);
  const tCxc = quoteSchemaTable(schema, "cuentas_por_cobrar");
  const tCob = quoteSchemaTable(schema, "cobros_clientes");
  const tFac = quoteSchemaTable(schema, "facturas");

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // Lock de la cuenta para serializar cobros concurrentes.
    const cq = await client.query(
      `SELECT id, cliente_id, venta_id, factura_id, total, saldo, estado FROM ${tCxc}
        WHERE empresa_id = $1::uuid AND id = $2::uuid FOR UPDATE`,
      [empresaId, input.cuenta_por_cobrar_id],
    );
    if (cq.rowCount === 0) throw new CobroError("Cuenta por cobrar no encontrada.", 404);
    const cxc = cq.rows[0];

    // Idempotencia: si ya existe un cobro con esta clave, devolverlo sin re-aplicar.
    if (input.idempotency_key) {
      const prev = await client.query(
        `SELECT id FROM ${tCob} WHERE empresa_id = $1::uuid AND idempotency_key = $2`,
        [empresaId, input.idempotency_key],
      );
      if ((prev.rowCount ?? 0) > 0) {
        await client.query("COMMIT");
        return { cobro_id: prev.rows[0].id, saldo_nuevo: round2(Number(cxc.saldo) || 0), estado: cxc.estado, ya_existia: true };
      }
    }

    if (cxc.estado === "anulado") throw new CobroError("La cuenta está anulada; no admite cobros.", 409);
    if (cxc.estado === "pagado") throw new CobroError("La cuenta ya está pagada.", 409);

    const saldoActual = round2(Number(cxc.saldo) || 0);
    const total = round2(Number(cxc.total) || 0);
    if (monto > saldoActual + 0.001) throw new CobroError(`El monto (${monto}) supera el saldo pendiente (${saldoActual}).`);

    const fechaPago = typeof input.fecha_pago === "string" && input.fecha_pago.trim() ? input.fecha_pago : new Date().toISOString();

    const ins = await client.query(
      `INSERT INTO ${tCob} (
         empresa_id, cliente_id, cuenta_por_cobrar_id, venta_id, fecha_pago, monto, metodo_pago,
         entidad_bancaria_id, entidad_nombre_snapshot, referencia, titular, observaciones,
         usuario_id, usuario_nombre, idempotency_key
       ) VALUES (
         $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::timestamptz, $6::numeric, $7,
         $8::uuid, $9, $10, $11, $12,
         $13::uuid, $14, $15
       ) RETURNING id`,
      [
        empresaId, cxc.cliente_id, cxc.id, cxc.venta_id ?? null, fechaPago, monto, metodoValido(input.metodo_pago),
        input.entidad_bancaria_id || null, input.entidad_nombre_snapshot?.trim() || null,
        input.referencia?.trim() || null, input.titular?.trim() || null, input.observaciones?.trim() || null,
        input.usuario_id || null, input.usuario_nombre?.trim() || null, input.idempotency_key || null,
      ],
    );
    const cobroId = ins.rows[0].id as string;

    const saldoNuevo = round2(Math.max(0, saldoActual - monto));
    const estadoNuevo = saldoNuevo <= 0.001 ? "pagado" : saldoNuevo < total ? "parcial" : "pendiente";
    await client.query(`UPDATE ${tCxc} SET saldo = $1::numeric, estado = $2, updated_at = now() WHERE empresa_id = $3::uuid AND id = $4::uuid`, [saldoNuevo, estadoNuevo, empresaId, cxc.id]);

    // Sincronizar la factura de origen (si aplica).
    if (cxc.factura_id) {
      const estadoFac = saldoNuevo <= 0.001 ? "Pagada" : "Pendiente";
      await client.query(`UPDATE ${tFac} SET saldo = $1::numeric, estado = $2, updated_at = now() WHERE empresa_id = $3::uuid AND id = $4::uuid`, [saldoNuevo, estadoFac, empresaId, cxc.factura_id]);
    }

    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "cobro",
      entidadId: cobroId,
      accion: "registrar",
      origen: "api/cobros",
      usuarioId: input.usuario_id || null,
      usuarioEmail: input.usuario_email || null,
      usuarioNombre: input.usuario_nombre || null,
      detalle: { cuenta_por_cobrar_id: cxc.id, monto, saldo_nuevo: saldoNuevo, estado: estadoNuevo },
    });

    await client.query("COMMIT");
    return { cobro_id: cobroId, saldo_nuevo: saldoNuevo, estado: estadoNuevo, ya_existia: false };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    if (e instanceof CobroError) throw e;
    // Violación de la unique de idempotencia por carrera exacta → tratar como duplicado.
    if ((e as { code?: string })?.code === "23505") {
      throw new CobroError("Cobro duplicado (reintento).", 409);
    }
    throw new CobroError(e instanceof Error ? e.message : "Error al registrar el cobro.", 500);
  } finally {
    client.release();
  }
}
