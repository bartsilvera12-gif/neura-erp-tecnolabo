/**
 * Anulación transaccional de un recibo de dinero.
 *
 * El recibo (`recibos_dinero`) es solo el COMPROBANTE. El efecto financiero lo
 * produjo su documento de origen:
 *   - origen 'cobro_cxc'  → un `cobros_clientes` que bajó el saldo de la
 *     `cuentas_por_cobrar` y sincronizó la `facturas` de origen.
 *   - origen 'venta_contado' → la venta (que además generó caja/stock).
 *   - origen 'manual'     → sin efecto financiero asociado.
 *
 * Por eso, anular NO es solo marcar el estado: para 'cobro_cxc' se revierte el
 * cobro (se restaura saldo/estado de la cuenta por cobrar y de la factura, y se
 * marca el cobro anulado para que deje de contar como cobranza). Todo en una
 * sola transacción (`BEGIN`/`COMMIT`/`ROLLBACK`) con `SELECT ... FOR UPDATE`,
 * siguiendo el molde de `registrarCobroPg` / `anularPagoProveedor`.
 *
 * Idempotente: si el recibo ya está anulado, lanza 409 sin re-aplicar.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

export class ReciboAnularError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.name = "ReciboAnularError";
    this.status = status;
  }
}

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

export interface AnularReciboInput {
  reciboId: string;
  motivo?: string | null;
  usuario: { id: string | null; email?: string | null; nombre?: string | null };
}

export interface AnularReciboResult {
  recibo_id: string;
  numero_recibo: string | null;
  origen: string;
  cobro_revertido: boolean;
  cuenta_por_cobrar_id: string | null;
  saldo_restaurado: number | null;
  factura_id: string | null;
}

export async function anularReciboPg(
  schema: string,
  empresaId: string,
  input: AnularReciboInput,
): Promise<AnularReciboResult> {
  assertAllowedChatDataSchema(schema);
  const motivo = (input.motivo ?? "").trim().slice(0, 500) || null;
  if (!input.reciboId) throw new ReciboAnularError("Falta el identificador del recibo.");

  const pool = getChatPostgresPool();
  if (!pool) throw new ReciboAnularError("Pool no disponible.", 500);
  const tRec = quoteSchemaTable(schema, "recibos_dinero");
  const tCob = quoteSchemaTable(schema, "cobros_clientes");
  const tCxc = quoteSchemaTable(schema, "cuentas_por_cobrar");
  const tFac = quoteSchemaTable(schema, "facturas");

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    // Lock del recibo para serializar anulaciones concurrentes.
    const rq = await client.query(
      `SELECT id, numero_recibo, origen, monto, venta_id, cuenta_por_cobrar_id, cobro_cliente_id,
              COALESCE(anulado, false) AS anulado, anulado_at
         FROM ${tRec}
        WHERE empresa_id = $1::uuid AND id = $2::uuid
        FOR UPDATE`,
      [empresaId, input.reciboId],
    );
    if (rq.rowCount === 0) throw new ReciboAnularError("Recibo no encontrado.", 404);
    const rec = rq.rows[0];
    const numeroRecibo = (rec.numero_recibo as string) ?? null;

    // Idempotencia: no anular dos veces.
    if (rec.anulado === true || rec.anulado_at != null) {
      throw new ReciboAnularError("El recibo ya está anulado.", 409);
    }

    const origen = String(rec.origen);
    let cobroRevertido = false;
    let saldoRestaurado: number | null = null;
    let cxcId: string | null = rec.cuenta_por_cobrar_id ? String(rec.cuenta_por_cobrar_id) : null;
    let facturaId: string | null = null;

    if (origen === "venta_contado") {
      // El recibo contado es el comprobante de una venta que además movió caja y
      // stock. Revertir eso desde acá duplicaría la lógica de anulación de venta
      // y podría dejar efectos inconsistentes. Se redirige al flujo correcto.
      throw new ReciboAnularError(
        `Este recibo (${numeroRecibo ?? ""}) corresponde a una venta contado. ` +
          `Para revertirlo, anulá la venta desde el módulo Ventas: eso repone el stock y el movimiento de caja.`,
        409,
      );
    }

    if (origen === "cobro_cxc") {
      const cobroId = rec.cobro_cliente_id ? String(rec.cobro_cliente_id) : null;
      if (cobroId) {
        // Lock del cobro subyacente.
        const cq = await client.query(
          `SELECT id, cuenta_por_cobrar_id, monto, (anulado_at IS NOT NULL) AS anulado
             FROM ${tCob}
            WHERE empresa_id = $1::uuid AND id = $2::uuid
            FOR UPDATE`,
          [empresaId, cobroId],
        );
        if ((cq.rowCount ?? 0) > 0) {
          const cob = cq.rows[0];
          const cobroMonto = round2(Number(cob.monto) || 0);
          cxcId = cob.cuenta_por_cobrar_id ? String(cob.cuenta_por_cobrar_id) : cxcId;

          // Si el cobro ya estaba anulado (p. ej. por una anulación previa), no
          // se re-restaura el saldo; solo se marca el recibo (más abajo).
          if (cob.anulado !== true) {
            if (cxcId) {
              // Lock de la cuenta por cobrar; restaurar saldo salvo que la cuenta
              // esté anulada (venta anulada → la deuda ya no existe).
              const xq = await client.query(
                `SELECT id, total, saldo, estado, factura_id
                   FROM ${tCxc}
                  WHERE empresa_id = $1::uuid AND id = $2::uuid
                  FOR UPDATE`,
                [empresaId, cxcId],
              );
              if ((xq.rowCount ?? 0) > 0) {
                const cxc = xq.rows[0];
                facturaId = cxc.factura_id ? String(cxc.factura_id) : null;
                if (String(cxc.estado) !== "anulado") {
                  const total = round2(Number(cxc.total) || 0);
                  const saldoActual = round2(Number(cxc.saldo) || 0);
                  const saldoNuevo = round2(Math.min(total, saldoActual + cobroMonto));
                  const estadoNuevo =
                    saldoNuevo <= 0.001 ? "pagado" : saldoNuevo < total ? "parcial" : "pendiente";
                  await client.query(
                    `UPDATE ${tCxc} SET saldo = $1::numeric, estado = $2, updated_at = now()
                       WHERE empresa_id = $3::uuid AND id = $4::uuid`,
                    [saldoNuevo, estadoNuevo, empresaId, cxcId],
                  );
                  saldoRestaurado = saldoNuevo;

                  // Sincronizar la factura de origen (si aplica y no está anulada).
                  if (facturaId) {
                    const fq = await client.query(
                      `SELECT id, estado FROM ${tFac}
                        WHERE empresa_id = $1::uuid AND id = $2::uuid
                        FOR UPDATE`,
                      [empresaId, facturaId],
                    );
                    if ((fq.rowCount ?? 0) > 0) {
                      const facEstado = String(fq.rows[0].estado ?? "").toLowerCase();
                      const esAnulada = facEstado === "anulado" || facEstado === "anulada";
                      if (!esAnulada) {
                        const estadoFac = saldoNuevo <= 0.001 ? "Pagada" : "Pendiente";
                        await client.query(
                          `UPDATE ${tFac} SET saldo = $1::numeric, estado = $2, updated_at = now()
                             WHERE empresa_id = $3::uuid AND id = $4::uuid`,
                          [saldoNuevo, estadoFac, empresaId, facturaId],
                        );
                      }
                    }
                  }
                }
              }
            }

            // Marcar el cobro como anulado (deja de contar como cobranza).
            await client.query(
              `UPDATE ${tCob} SET anulado_at = now(), anulado_por = $1::uuid, anulado_motivo = $2
                 WHERE empresa_id = $3::uuid AND id = $4::uuid`,
              [input.usuario.id, motivo, empresaId, cobroId],
            );
            cobroRevertido = true;
          }
        }
      }
    }

    // Marcar el recibo como anulado (número y datos históricos se conservan).
    await client.query(
      `UPDATE ${tRec}
          SET anulado = true, anulado_at = now(), anulado_por = $1::uuid, anulado_motivo = $2, updated_at = now()
        WHERE empresa_id = $3::uuid AND id = $4::uuid`,
      [input.usuario.id, motivo, empresaId, input.reciboId],
    );

    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "recibo_dinero",
      entidadId: input.reciboId,
      accion: "anular",
      origen: "api/recibos-dinero",
      usuarioId: input.usuario.id ?? null,
      usuarioEmail: input.usuario.email ?? null,
      usuarioNombre: input.usuario.nombre ?? null,
      detalle: {
        numero_recibo: numeroRecibo,
        origen,
        cobro_cliente_id: rec.cobro_cliente_id ?? null,
        cuenta_por_cobrar_id: cxcId,
        saldo_restaurado: saldoRestaurado,
        factura_id: facturaId,
        motivo,
      },
    });

    await client.query("COMMIT");
    return {
      recibo_id: input.reciboId,
      numero_recibo: numeroRecibo,
      origen,
      cobro_revertido: cobroRevertido,
      cuenta_por_cobrar_id: cxcId,
      saldo_restaurado: saldoRestaurado,
      factura_id: facturaId,
    };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    if (e instanceof ReciboAnularError) throw e;
    throw new ReciboAnularError(e instanceof Error ? e.message : "No se pudo anular el recibo.", 500);
  } finally {
    client.release();
  }
}
