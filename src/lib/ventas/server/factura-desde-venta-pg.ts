/**
 * Puente venta → factura, para poder emitir FACTURA ELECTRÓNICA (SIFEN) desde
 * una venta del POS.
 *
 * El pipeline SIFEN (`/api/facturas/[id]/sifen/*`) trabaja exclusivamente sobre
 * `facturas`. Este módulo crea esa factura a partir de la venta, con sus ítems,
 * y a partir de ahí el circuito fiscal es el mismo que ya se usa: generar el
 * borrador, firmar, enviar y obtener el KuDE.
 *
 * Idempotente: una venta tiene a lo sumo una factura (índice único sobre
 * `venta_id`). Reintentar no consume numeración fiscal de más.
 *
 * NO toca stock (la venta ya lo descontó) ni genera cuenta por cobrar acá: la
 * venta a crédito ya creó la suya al registrarse.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

/** La venta no puede facturarse todavía (anulada, sin cliente, sin ítems…). */
export class VentaNoFacturableError extends Error {
  constructor(mensaje: string) {
    super(mensaje);
    this.name = "VentaNoFacturableError";
  }
}

export interface Usuario {
  id?: string | null;
  nombre?: string | null;
  email?: string | null;
}

export interface FacturaDesdeVenta {
  factura_id: string;
  numero_factura: string;
  /** true si ya existía: no se creó nada nuevo. */
  yaExistia: boolean;
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool no disponible.");
  return p;
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

export async function crearFacturaDesdeVenta(
  schema: string,
  empresaId: string,
  ventaId: string,
  usuario: Usuario,
): Promise<FacturaDesdeVenta> {
  assertAllowedChatDataSchema(schema);
  const tV = quoteSchemaTable(schema, "ventas");
  const tVI = quoteSchemaTable(schema, "ventas_items");
  const tFac = quoteSchemaTable(schema, "facturas");
  const tFacItems = quoteSchemaTable(schema, "factura_items");
  const fnNumero = `"${schema}".next_numero_factura_empresa`;

  const client = await pool().connect();
  try {
    await client.query("BEGIN");

    // 1) Venta bloqueada + validaciones.
    const vq = await client.query(
      `SELECT * FROM ${tV} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [ventaId, empresaId],
    );
    if (vq.rowCount === 0) throw new VentaNoFacturableError("Venta no encontrada.");
    const v = vq.rows[0];

    if (v.anulada_at) throw new VentaNoFacturableError("La venta está anulada; no se puede facturar.");
    if (!v.cliente_id) {
      throw new VentaNoFacturableError(
        "La venta no tiene cliente asignado. La factura electrónica necesita un receptor: asigná el cliente y volvé a intentar.",
      );
    }

    // 2) Idempotencia: si esta venta ya tiene factura, se devuelve esa.
    const yaQ = await client.query(
      `SELECT id, numero_factura FROM ${tFac} WHERE venta_id = $1::uuid AND empresa_id = $2::uuid LIMIT 1`,
      [ventaId, empresaId],
    );
    if ((yaQ.rowCount ?? 0) > 0) {
      await client.query("COMMIT");
      return {
        factura_id: String(yaQ.rows[0].id),
        numero_factura: String(yaQ.rows[0].numero_factura),
        yaExistia: true,
      };
    }

    // 3) Ítems de la venta.
    const itq = await client.query(
      `SELECT producto_id, producto_nombre, sku, cantidad, precio_venta, tipo_iva,
              subtotal, monto_iva, total_linea
         FROM ${tVI} WHERE venta_id = $1::uuid AND empresa_id = $2::uuid ORDER BY created_at`,
      [ventaId, empresaId],
    );
    if (itq.rowCount === 0) throw new VentaNoFacturableError("La venta no tiene ítems.");

    // 4) Numeración correlativa: la MISMA función que usa la conversión de
    //    presupuesto, para no abrir una segunda serie de numeración fiscal.
    const numRes = await client.query(`SELECT ${fnNumero}($1::uuid, $2::text) AS numero`, [empresaId, "FAC-"]);
    const numeroFactura = String(numRes.rows[0].numero);

    const tipoPago = String(v.tipo_venta ?? "").toUpperCase() === "CREDITO" ? "credito" : "contado";
    const total = num(v.total);
    const saldo = tipoPago === "credito" ? total : 0;
    const diasVenc = tipoPago === "credito" ? Math.max(0, num(v.plazo_dias)) : 0;

    const facRes = await client.query(
      `INSERT INTO ${tFac} (
         empresa_id, cliente_id, numero_factura, fecha, fecha_vencimiento,
         monto, saldo, estado, tipo, moneda, venta_id, numero_orden_compra
       ) VALUES (
         $1::uuid, $2::uuid, $3, CURRENT_DATE, (CURRENT_DATE + ($4 || ' days')::interval)::date,
         $5, $6, 'Pendiente', $7, $8, $9::uuid, $10
       ) RETURNING id`,
      [
        empresaId,
        v.cliente_id,
        numeroFactura,
        String(diasVenc),
        total,
        saldo,
        tipoPago,
        v.moneda ?? "PYG",
        ventaId,
        v.numero_orden_compra ?? null,
      ],
    );
    const facturaId = String(facRes.rows[0].id);

    // 5) Ítems de la factura. El IVA por línea sale de la venta ya calculado.
    for (const it of itq.rows) {
      await client.query(
        `INSERT INTO ${tFacItems} (
           factura_id, empresa_id, descripcion, producto_id, sku,
           cantidad, precio_unitario, descuento, subtotal, iva, total
         ) VALUES (
           $1::uuid, $2::uuid, $3, $4::uuid, $5,
           $6, $7, 0, $8, $9, $10
         )`,
        [
          facturaId,
          empresaId,
          it.producto_nombre,
          it.producto_id ?? null,
          it.sku ?? null,
          num(it.cantidad),
          num(it.precio_venta),
          num(it.subtotal),
          num(it.monto_iva),
          num(it.total_linea),
        ],
      );
    }

    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "factura",
      entidadId: facturaId,
      accion: "crear",
      origen: "api/ventas/factura-electronica",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { numero_factura: numeroFactura, venta_id: ventaId, items: itq.rowCount },
    });

    await client.query("COMMIT");
    return { factura_id: facturaId, numero_factura: numeroFactura, yaExistia: false };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}
