/**
 * Listado global de recibos de dinero (auditoría).
 *
 * Un recibo nace de dos lugares:
 *   - `cobro_cxc`     → cobro de una cuenta por cobrar (venta a crédito)
 *   - `venta_contado` → cobro en el momento de la venta
 *
 * El caso que motiva el módulo es el primero: llevar control de todo lo que se
 * le cobra a un cliente a crédito. El segundo se lista igual y se puede filtrar.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface FiltrosRecibos {
  desde?: string | null;
  hasta?: string | null;
  clienteId?: string | null;
  origen?: string | null;
  metodoPago?: string | null;
  /** Incluir anulados. Por defecto se listan todos. */
  soloVigentes?: boolean;
  /** Busca en número, cliente, concepto y referencia. */
  texto?: string | null;
  limit?: number;
  offset?: number;
}

export interface ReciboListadoRow {
  id: string;
  numero_recibo: string;
  fecha: string;
  cliente_id: string | null;
  cliente_nombre: string | null;
  cliente_documento: string | null;
  origen: string;
  moneda: string;
  monto: number;
  metodo_pago: string | null;
  referencia: string | null;
  concepto: string | null;
  usuario_nombre: string | null;
  anulado: boolean;
  venta_numero: string | null;
  /** Número de factura de la cuenta por cobrar, cuando el recibo viene de un cobro. */
  factura_numero: string | null;
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool no disponible.");
  return p;
}

export async function listarRecibosGlobal(
  schema: string,
  empresaId: string,
  f: FiltrosRecibos = {},
): Promise<{ rows: ReciboListadoRow[]; total: number; sumaVigente: number }> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "recibos_dinero");
  const tV = quoteSchemaTable(schema, "ventas");
  const tCxc = quoteSchemaTable(schema, "cuentas_por_cobrar");
  const tF = quoteSchemaTable(schema, "facturas");

  const cond: string[] = ["r.empresa_id = $1::uuid"];
  const vals: unknown[] = [empresaId];
  const add = (sql: string, v: unknown) => {
    vals.push(v);
    cond.push(sql.replace("$$", "$" + vals.length));
  };

  if (f.desde) add("r.fecha >= $$::timestamptz", f.desde);
  if (f.hasta) add("r.fecha < ($$::date + interval '1 day')", f.hasta);
  if (f.clienteId) add("r.cliente_id = $$::uuid", f.clienteId);
  if (f.origen) add("r.origen = $$", f.origen);
  if (f.metodoPago) add("r.metodo_pago = $$", f.metodoPago);
  if (f.soloVigentes) cond.push("COALESCE(r.anulado, false) = false");
  if (f.texto) {
    vals.push("%" + f.texto.trim() + "%");
    const i = "$" + vals.length;
    cond.push(
      `(r.numero_recibo ILIKE ${i} OR COALESCE(r.cliente_nombre,'') ILIKE ${i}
        OR COALESCE(r.concepto,'') ILIKE ${i} OR COALESCE(r.referencia,'') ILIKE ${i})`,
    );
  }

  const from = `
    FROM ${tR} r
    LEFT JOIN ${tV} v   ON v.id = r.venta_id
    LEFT JOIN ${tCxc} x ON x.id = r.cuenta_por_cobrar_id
    LEFT JOIN ${tF} f   ON f.id = x.factura_id
   WHERE ${cond.join(" AND ")}`;

  const limit = Math.min(Math.max(Number(f.limit) || 200, 1), 500);
  const offset = Math.max(Number(f.offset) || 0, 0);

  const client = await pool().connect();
  try {
    const tot = await client.query(
      `SELECT count(*)::int AS n,
              COALESCE(SUM(CASE WHEN COALESCE(r.anulado,false) = false THEN r.monto ELSE 0 END), 0)::numeric AS suma
         ${from}`,
      vals,
    );

    const q = await client.query(
      `SELECT r.id, r.numero_recibo, r.fecha, r.cliente_id, r.cliente_nombre, r.cliente_documento,
              r.origen, r.moneda, r.monto, r.metodo_pago, r.referencia, r.concepto,
              r.usuario_nombre, COALESCE(r.anulado, false) AS anulado,
              v.numero_control AS venta_numero,
              f.numero_factura AS factura_numero
         ${from}
        ORDER BY r.fecha DESC, r.numero_recibo DESC
        LIMIT ${limit} OFFSET ${offset}`,
      vals,
    );

    const rows: ReciboListadoRow[] = q.rows.map((r) => ({
      id: String(r.id),
      numero_recibo: String(r.numero_recibo),
      fecha: String(r.fecha),
      cliente_id: (r.cliente_id as string) ?? null,
      cliente_nombre: (r.cliente_nombre as string) ?? null,
      cliente_documento: (r.cliente_documento as string) ?? null,
      origen: String(r.origen ?? ""),
      moneda: String(r.moneda ?? "PYG"),
      monto: Number(r.monto) || 0,
      metodo_pago: (r.metodo_pago as string) ?? null,
      referencia: (r.referencia as string) ?? null,
      concepto: (r.concepto as string) ?? null,
      usuario_nombre: (r.usuario_nombre as string) ?? null,
      anulado: r.anulado === true,
      venta_numero: (r.venta_numero as string) ?? null,
      factura_numero: (r.factura_numero as string) ?? null,
    }));

    return {
      rows,
      total: Number(tot.rows[0].n) || 0,
      sumaVigente: Number(tot.rows[0].suma) || 0,
    };
  } finally {
    client.release();
  }
}
