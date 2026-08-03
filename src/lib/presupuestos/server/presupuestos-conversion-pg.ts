/**
 * Conversión de presupuesto aprobado → factura (Fase 1).
 *
 * IDEMPOTENTE por diseño: la tabla `presupuesto_conversiones` tiene
 * UNIQUE(presupuesto_id); el INSERT ... ON CONFLICT DO NOTHING actúa como
 * candado a nivel BD contra doble clic / reintento HTTP. Un segundo intento
 * devuelve la MISMA factura, nunca crea una segunda.
 *
 * Reglas del alcance:
 *  - Copia cantidades, precios, descuentos, moneda e impuestos del presupuesto.
 *  - En la factura, la descripción del ítem es SOLO el nombre comercial
 *    (no se copian especificaciones técnicas al concepto fiscal).
 *  - Guarda la relación presupuesto↔factura (facturas.presupuesto_id +
 *    presupuesto_conversiones) para poder ver el presupuesto desde la factura.
 *  - Transacción atómica (BEGIN/COMMIT/ROLLBACK) con auditoría.
 *
 * NO descuenta stock: en este cliente el stock sale por nota de remisión
 * (feature flag stock_salida_por_remision, Fases 5–6).
 */
import type { PoolClient } from "pg";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

export class PresupuestoNoConvertibleError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = "PresupuestoNoConvertibleError";
  }
}

export interface ConvertirPresupuestoInput {
  presupuestoId: string;
  usuarioId?: string | null;
  usuarioNombre?: string | null;
  usuarioEmail?: string | null;
  /** 'contado' | 'credito'. Default 'credito'. */
  tipoPago?: string;
  /** Días para el vencimiento de la factura (crédito). Default 30. */
  diasVencimiento?: number;
}

export interface ConvertirPresupuestoResult {
  facturaId: string;
  numeroFactura: string;
  yaExistia: boolean;
}

async function cargarNumeroFactura(
  client: PoolClient,
  schema: string,
  empresaId: string,
  facturaId: string,
): Promise<string> {
  const tFac = quoteSchemaTable(schema, "facturas");
  const r = await client.query(
    `SELECT numero_factura FROM ${tFac} WHERE id = $1::uuid AND empresa_id = $2::uuid`,
    [facturaId, empresaId],
  );
  return (r.rows[0]?.numero_factura as string) ?? "";
}

export async function convertirPresupuestoAFactura(
  schema: string,
  empresaId: string,
  input: ConvertirPresupuestoInput,
): Promise<ConvertirPresupuestoResult> {
  assertAllowedChatDataSchema(schema);
  const pool = getChatPostgresPool();
  if (!pool) throw new Error("Pool no disponible.");

  const tPre = quoteSchemaTable(schema, "presupuestos");
  const tPreItems = quoteSchemaTable(schema, "presupuesto_items");
  const tConv = quoteSchemaTable(schema, "presupuesto_conversiones");
  const tFac = quoteSchemaTable(schema, "facturas");
  const tFacItems = quoteSchemaTable(schema, "factura_items");
  const tHist = quoteSchemaTable(schema, "presupuesto_estado_historial");
  const fnNumero = `"${schema}".next_numero_factura_empresa`;

  const tipoPago = input.tipoPago === "contado" ? "contado" : "credito";
  const diasVenc = Number.isFinite(input.diasVencimiento) ? Number(input.diasVencimiento) : 30;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // 1) Candado idempotente. Si ya había conversión, devolvemos su factura.
    const guard = await client.query(
      `INSERT INTO ${tConv} (empresa_id, presupuesto_id, tipo_destino, created_by)
         VALUES ($1::uuid, $2::uuid, 'factura', $3::uuid)
       ON CONFLICT (presupuesto_id) DO NOTHING
       RETURNING id`,
      [empresaId, input.presupuestoId, input.usuarioId ?? null],
    );

    if (guard.rowCount === 0) {
      const prev = await client.query(
        `SELECT factura_id FROM ${tConv} WHERE presupuesto_id = $1::uuid AND empresa_id = $2::uuid`,
        [input.presupuestoId, empresaId],
      );
      const facturaId = prev.rows[0]?.factura_id as string | null;
      await client.query("COMMIT");
      if (!facturaId) {
        // Conversión en curso por otra request; el caller puede reintentar.
        throw new PresupuestoNoConvertibleError("Conversión en curso; reintente en unos segundos.");
      }
      return {
        facturaId,
        numeroFactura: await cargarNumeroFacturaFuera(schema, empresaId, facturaId),
        yaExistia: true,
      };
    }
    const conversionId = guard.rows[0].id as string;

    // 2) Presupuesto bloqueado + validaciones.
    const preRes = await client.query(`SELECT * FROM ${tPre} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [
      input.presupuestoId,
      empresaId,
    ]);
    if (preRes.rowCount === 0) throw new PresupuestoNoConvertibleError("Presupuesto no encontrado.");
    const pre = preRes.rows[0];
    if (pre.estado !== "aprobado") {
      throw new PresupuestoNoConvertibleError(
        `Solo se puede convertir un presupuesto en estado 'aprobado' (actual: '${pre.estado}').`,
      );
    }
    if (!pre.cliente_id) {
      throw new PresupuestoNoConvertibleError("El presupuesto no tiene cliente asignado; no se puede facturar.");
    }

    // 3) Numeración correlativa de factura (misma función que /api/facturas).
    const numRes = await client.query(`SELECT ${fnNumero}($1::uuid, $2::text) AS numero`, [empresaId, "FAC-"]);
    const numeroFactura = numRes.rows[0].numero as string;

    // 4) Cabecera de factura.
    const total = Number(pre.total) || 0;
    const saldo = tipoPago === "credito" ? total : 0;
    const facRes = await client.query(
      `INSERT INTO ${tFac} (
         empresa_id, cliente_id, numero_factura, fecha, fecha_vencimiento,
         monto, saldo, estado, tipo, moneda, presupuesto_id
       ) VALUES (
         $1::uuid, $2::uuid, $3, CURRENT_DATE, (CURRENT_DATE + ($4 || ' days')::interval)::date,
         $5, $6, 'Pendiente', $7, $8, $9::uuid
       ) RETURNING id`,
      [empresaId, pre.cliente_id, numeroFactura, String(diasVenc), total, saldo, tipoPago, pre.moneda, input.presupuestoId],
    );
    const facturaId = facRes.rows[0].id as string;

    // 5) Ítems: descripción = SOLO nombre comercial (sin especificaciones técnicas).
    const items = await client.query(
      `SELECT producto_id, producto_nombre, sku, cantidad, precio_unitario, descuento, subtotal, monto_iva, total
         FROM ${tPreItems} WHERE presupuesto_id = $1::uuid AND empresa_id = $2::uuid ORDER BY created_at`,
      [input.presupuestoId, empresaId],
    );
    for (const it of items.rows) {
      await client.query(
        `INSERT INTO ${tFacItems} (
           factura_id, empresa_id, descripcion, producto_id, sku,
           cantidad, precio_unitario, descuento, subtotal, iva, total
         ) VALUES (
           $1::uuid, $2::uuid, $3, $4::uuid, $5,
           $6, $7, $8, $9, $10, $11
         )`,
        [
          facturaId,
          empresaId,
          it.producto_nombre, // nombre comercial, NO especificaciones
          it.producto_id ?? null,
          it.sku ?? null,
          it.cantidad,
          it.precio_unitario,
          it.descuento ?? 0,
          it.subtotal ?? 0,
          it.monto_iva ?? 0,
          it.total ?? 0,
        ],
      );
    }

    // 6) Marca presupuesto convertido + vínculo.
    await client.query(
      `UPDATE ${tPre}
          SET estado = 'convertido', convertido_factura_id = $1::uuid,
              convertido_at = now(), convertido_por = $2::uuid, updated_at = now()
        WHERE id = $3::uuid AND empresa_id = $4::uuid`,
      [facturaId, input.usuarioId ?? null, input.presupuestoId, empresaId],
    );
    await client.query(`UPDATE ${tConv} SET factura_id = $1::uuid WHERE id = $2::uuid`, [facturaId, conversionId]);

    // 7) Historial de estado.
    await client.query(
      `INSERT INTO ${tHist} (empresa_id, presupuesto_id, estado_anterior, estado_nuevo, observacion, usuario_id, usuario_nombre)
         VALUES ($1::uuid, $2::uuid, 'aprobado', 'convertido', $3, $4::uuid, $5)`,
      [empresaId, input.presupuestoId, `Convertido a factura ${numeroFactura}`, input.usuarioId ?? null, input.usuarioNombre ?? null],
    );

    // 8) Auditoría.
    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "presupuesto",
      entidadId: input.presupuestoId,
      accion: "convertir_a_factura",
      origen: "api/presupuestos/convertir-factura",
      usuarioId: input.usuarioId ?? null,
      usuarioEmail: input.usuarioEmail ?? null,
      usuarioNombre: input.usuarioNombre ?? null,
      detalle: { factura_id: facturaId, numero_factura: numeroFactura, total, tipo_pago: tipoPago },
    });

    await client.query("COMMIT");
    return { facturaId, numeroFactura, yaExistia: false };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

/** Lectura auxiliar del número de factura fuera de la tx (para el caso ya-existía). */
async function cargarNumeroFacturaFuera(schema: string, empresaId: string, facturaId: string): Promise<string> {
  const pool = getChatPostgresPool();
  if (!pool) return "";
  const client = await pool.connect();
  try {
    return await cargarNumeroFactura(client, schema, empresaId, facturaId);
  } finally {
    client.release();
  }
}
