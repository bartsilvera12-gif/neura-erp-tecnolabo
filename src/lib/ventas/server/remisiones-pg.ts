/**
 * Notas de remisión / entregas parciales (Fase 5+6).
 *
 * Varias remisiones por factura. El stock sale al CONFIRMAR cada remisión
 * (helper F0), no al emitir la factura. Valida no entregar más de lo facturado.
 * Actualiza factura_items.cantidad_entregada y facturas.estado_entrega.
 * La anulación repone stock (movimientos inversos) y revierte lo entregado.
 */
import type { PoolClient } from "pg";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import {
  registrarMovimientoInventarioTx,
  revertirMovimientosDeDocumentoTx,
  StockInsuficienteMovimientoError,
} from "@/lib/inventario/server/stock-core-pg";
import { getEmpresaConfigTx } from "@/lib/config/server/empresa-config-pg";
import { siguienteCorrelativoTx } from "@/lib/documentos/server/correlativo-pg";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

export { StockInsuficienteMovimientoError };

export class RemisionExcedenteError extends Error {
  producto: string;
  disponible: number;
  intentado: number;
  constructor(producto: string, disponible: number, intentado: number) {
    super(`No se puede remitir ${intentado} de "${producto}": disponible para remitir ${disponible}.`);
    this.name = "RemisionExcedenteError";
    this.producto = producto;
    this.disponible = disponible;
    this.intentado = intentado;
  }
}

export interface LineaEntrega {
  factura_item_id: string;
  producto_id: string;
  producto_nombre: string;
  sku: string | null;
  cantidad_facturada: number;
  cantidad_entregada: number;
  disponible: number;
  costo_unitario: number;
}
export interface ResumenFacturaEntrega {
  factura_id: string;
  numero_factura: string;
  estado_entrega: string;
  lineas: LineaEntrega[];
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool no disponible.");
  return p;
}

/** Resumen facturado/entregado/pendiente por ítem de una factura. */
export async function getResumenFacturaEntrega(
  schema: string,
  empresaId: string,
  facturaId: string,
): Promise<ResumenFacturaEntrega | null> {
  assertAllowedChatDataSchema(schema);
  const tF = quoteSchemaTable(schema, "facturas");
  const tFI = quoteSchemaTable(schema, "factura_items");
  const tP = quoteSchemaTable(schema, "productos");
  const client = await pool().connect();
  try {
    const fac = await client.query(`SELECT id, numero_factura, estado_entrega FROM ${tF} WHERE id = $1::uuid AND empresa_id = $2::uuid`, [facturaId, empresaId]);
    if (fac.rowCount === 0) return null;
    const items = await client.query(
      `SELECT fi.id, fi.producto_id, fi.descripcion AS producto_nombre, fi.sku,
              COALESCE(fi.cantidad,0)::numeric AS cantidad, COALESCE(fi.cantidad_entregada,0)::numeric AS cantidad_entregada,
              COALESCE(p.costo_promedio,0)::numeric AS costo_unitario
         FROM ${tFI} fi
         LEFT JOIN ${tP} p ON p.id = fi.producto_id
        WHERE fi.factura_id = $1::uuid AND fi.empresa_id = $2::uuid
        ORDER BY fi.created_at`,
      [facturaId, empresaId],
    );
    const lineas: LineaEntrega[] = items.rows.map((r) => {
      const facturada = Number(r.cantidad) || 0;
      const entregada = Number(r.cantidad_entregada) || 0;
      return {
        factura_item_id: r.id,
        producto_id: r.producto_id,
        producto_nombre: r.producto_nombre,
        sku: r.sku,
        cantidad_facturada: facturada,
        cantidad_entregada: entregada,
        disponible: Math.max(0, facturada - entregada),
        costo_unitario: Number(r.costo_unitario) || 0,
      };
    });
    return {
      factura_id: facturaId,
      numero_factura: fac.rows[0].numero_factura,
      estado_entrega: fac.rows[0].estado_entrega,
      lineas,
    };
  } finally {
    client.release();
  }
}

async function recomputarEstadoEntregaFactura(client: PoolClient, schema: string, empresaId: string, facturaId: string) {
  const tF = quoteSchemaTable(schema, "facturas");
  const tFI = quoteSchemaTable(schema, "factura_items");
  const agg = await client.query(
    `SELECT COALESCE(SUM(cantidad),0)::numeric AS fact, COALESCE(SUM(cantidad_entregada),0)::numeric AS entr
       FROM ${tFI} WHERE factura_id = $1::uuid AND empresa_id = $2::uuid`,
    [facturaId, empresaId],
  );
  const fact = Number(agg.rows[0].fact) || 0;
  const entr = Number(agg.rows[0].entr) || 0;
  const estado = entr <= 0 ? "pendiente" : entr >= fact ? "entregada" : "parcialmente_entregada";
  await client.query(`UPDATE ${tF} SET estado_entrega = $1, updated_at = now() WHERE id = $2::uuid AND empresa_id = $3::uuid`, [estado, facturaId, empresaId]);
}

export interface RemisionItemInput {
  factura_item_id: string;
  producto_id: string;
  producto_nombre: string;
  sku?: string | null;
  cantidad: number;
  costo_unitario?: number;
}
export interface CrearRemisionInput {
  factura_id: string;
  deposito_id?: string | null;
  sucursal_id?: string | null;
  observacion?: string | null;
  firma_entrega?: string | null;
  firma_recepcion?: string | null;
  items: RemisionItemInput[];
  confirmar?: boolean;
}
export interface Usuario {
  id?: string | null;
  nombre?: string | null;
  email?: string | null;
}

async function confirmarRemisionTx(client: PoolClient, schema: string, empresaId: string, remisionId: string, usuario: Usuario): Promise<void> {
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const tFI = quoteSchemaTable(schema, "factura_items");

  const rem = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [remisionId, empresaId]);
  if (rem.rowCount === 0) throw new Error("Remisión no encontrada.");
  const r = rem.rows[0];
  if (r.estado !== "borrador") throw new Error(`La remisión no está en borrador (estado: ${r.estado}).`);

  const cfg = await getEmpresaConfigTx(client, schema, empresaId);
  const items = await client.query(`SELECT * FROM ${tRI} WHERE remision_id = $1::uuid ORDER BY created_at`, [remisionId]);

  for (const it of items.rows) {
    const cantidad = Number(it.cantidad) || 0;
    if (cantidad <= 0) continue;

    // Validar contra lo disponible del ítem de factura.
    if (it.factura_item_id) {
      const fi = await client.query(
        `SELECT COALESCE(cantidad,0)::numeric AS cant, COALESCE(cantidad_entregada,0)::numeric AS entr
           FROM ${tFI} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
        [it.factura_item_id, empresaId],
      );
      if ((fi.rowCount ?? 0) > 0) {
        const disponible = Number(fi.rows[0].cant) - Number(fi.rows[0].entr);
        if (cantidad > disponible) throw new RemisionExcedenteError(it.producto_nombre, disponible, cantidad);
        await client.query(`UPDATE ${tFI} SET cantidad_entregada = cantidad_entregada + $1::numeric WHERE id = $2::uuid`, [cantidad, it.factura_item_id]);
      }
    }

    // SALIDA de inventario al confirmar la entrega.
    await registrarMovimientoInventarioTx(
      client,
      schema,
      {
        empresaId,
        productoId: it.producto_id,
        productoNombre: it.producto_nombre,
        productoSku: it.sku ?? "",
        tipo: "SALIDA",
        cantidad,
        costoUnitario: Number(it.costo_unitario) || 0,
        origen: "remision",
        referencia: r.numero,
        documentoTipo: "remision",
        documentoId: remisionId,
        depositoId: r.deposito_id ?? null,
        sucursalId: r.sucursal_id ?? null,
        observacion: it.observacion ?? null,
        usuarioId: usuario.id ?? null,
        usuarioNombre: usuario.nombre ?? null,
      },
      { permitirStockNegativo: cfg.permitir_stock_negativo, onInsuficiente: "throw" },
    );
  }

  await client.query(
    `UPDATE ${tR} SET estado = 'confirmada', confirmada_at = now(), usuario_confirmador_id = $1::uuid, usuario_confirmador_nombre = $2, updated_at = now() WHERE id = $3::uuid`,
    [usuario.id ?? null, usuario.nombre ?? null, remisionId],
  );
  await recomputarEstadoEntregaFactura(client, schema, empresaId, r.factura_id);

  await registrarAuditoriaTx(client, schema, {
    empresaId,
    entidad: "remision",
    entidadId: remisionId,
    accion: "confirmar",
    origen: "api/remisiones",
    usuarioId: usuario.id ?? null,
    usuarioEmail: usuario.email ?? null,
    usuarioNombre: usuario.nombre ?? null,
    detalle: { numero: r.numero, factura_id: r.factura_id },
  });
}

export async function crearRemision(schema: string, empresaId: string, input: CrearRemisionInput, usuario: Usuario): Promise<{ remision_id: string; numero: string; confirmada: boolean }> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const tF = quoteSchemaTable(schema, "facturas");
  if (!input.items || input.items.length === 0) throw new Error("La remisión no tiene ítems.");

  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const fac = await client.query(`SELECT cliente_id FROM ${tF} WHERE id = $1::uuid AND empresa_id = $2::uuid`, [input.factura_id, empresaId]);
    if (fac.rowCount === 0) throw new Error("Factura no encontrada.");

    const { numero } = await siguienteCorrelativoTx(client, schema, empresaId, "remision", { prefijo: "REM" });
    const rem = await client.query(
      `INSERT INTO ${tR} (
         empresa_id, numero, factura_id, cliente_id, deposito_id, sucursal_id, observacion, estado,
         firma_entrega, firma_recepcion, usuario_creador_id, usuario_creador_nombre
       ) VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $5::uuid, $6::uuid, $7, 'borrador', $8, $9, $10::uuid, $11) RETURNING id`,
      [empresaId, numero, input.factura_id, fac.rows[0].cliente_id ?? null, input.deposito_id ?? null, input.sucursal_id ?? null, input.observacion ?? null, input.firma_entrega ?? null, input.firma_recepcion ?? null, usuario.id ?? null, usuario.nombre ?? null],
    );
    const remisionId = rem.rows[0].id as string;

    for (const it of input.items) {
      await client.query(
        `INSERT INTO ${tRI} (empresa_id, remision_id, factura_item_id, producto_id, producto_nombre, sku, cantidad, costo_unitario, observacion)
           VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5, $6, $7::numeric, $8::numeric, $9)`,
        [empresaId, remisionId, it.factura_item_id ?? null, it.producto_id, it.producto_nombre, it.sku ?? null, Number(it.cantidad) || 0, Number(it.costo_unitario) || 0, null],
      );
    }

    if (input.confirmar) await confirmarRemisionTx(client, schema, empresaId, remisionId, usuario);
    await client.query("COMMIT");
    return { remision_id: remisionId, numero, confirmada: !!input.confirmar };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export async function confirmarRemision(schema: string, empresaId: string, remisionId: string, usuario: Usuario): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    await confirmarRemisionTx(client, schema, empresaId, remisionId, usuario);
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export async function anularRemision(schema: string, empresaId: string, remisionId: string, usuario: Usuario, motivo: string): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const tFI = quoteSchemaTable(schema, "factura_items");
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const rem = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [remisionId, empresaId]);
    if (rem.rowCount === 0) throw new Error("Remisión no encontrada.");
    const r = rem.rows[0];
    if (r.estado !== "confirmada") throw new Error(`Solo se anula una remisión confirmada (estado: ${r.estado}).`);

    await revertirMovimientosDeDocumentoTx(client, schema, {
      empresaId,
      documentoTipo: "remision",
      documentoId: remisionId,
      usuarioId: usuario.id ?? null,
      usuarioNombre: usuario.nombre ?? null,
      motivo: `Anulación remisión ${r.numero}: ${motivo}`,
    });

    const items = await client.query(`SELECT factura_item_id, cantidad FROM ${tRI} WHERE remision_id = $1::uuid`, [remisionId]);
    for (const it of items.rows) {
      if (!it.factura_item_id) continue;
      await client.query(`UPDATE ${tFI} SET cantidad_entregada = GREATEST(0, cantidad_entregada - $1::numeric) WHERE id = $2::uuid AND empresa_id = $3::uuid`, [Number(it.cantidad) || 0, it.factura_item_id, empresaId]);
    }
    await recomputarEstadoEntregaFactura(client, schema, empresaId, r.factura_id);

    await client.query(`UPDATE ${tR} SET estado = 'anulada', anulada_at = now(), anulada_por = $1::uuid, anulada_motivo = $2, updated_at = now() WHERE id = $3::uuid`, [usuario.id ?? null, motivo, remisionId]);

    await registrarAuditoriaTx(client, schema, {
      empresaId, entidad: "remision", entidadId: remisionId, accion: "anular", origen: "api/remisiones",
      usuarioId: usuario.id ?? null, usuarioEmail: usuario.email ?? null, usuarioNombre: usuario.nombre ?? null,
      detalle: { numero: r.numero, motivo },
    });
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export interface RemisionResumen {
  id: string;
  numero: string;
  estado: string;
  fecha: string;
  factura_id: string;
  total_items: number;
}
export async function listRemisionesDeFactura(schema: string, empresaId: string, facturaId: string): Promise<RemisionResumen[]> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const client = await pool().connect();
  try {
    const res = await client.query(
      `SELECT r.id, r.numero, r.estado, r.fecha, r.factura_id,
              (SELECT COUNT(*) FROM ${tRI} i WHERE i.remision_id = r.id)::int AS total_items
         FROM ${tR} r WHERE r.empresa_id = $1::uuid AND r.factura_id = $2::uuid ORDER BY r.created_at DESC`,
      [empresaId, facturaId],
    );
    return res.rows as RemisionResumen[];
  } finally {
    client.release();
  }
}

export async function getRemision(schema: string, empresaId: string, remisionId: string) {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const tF = quoteSchemaTable(schema, "facturas");
  const client = await pool().connect();
  try {
    const rem = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid`, [remisionId, empresaId]);
    if (rem.rowCount === 0) return null;
    const items = await client.query(`SELECT * FROM ${tRI} WHERE remision_id = $1::uuid ORDER BY created_at`, [remisionId]);
    const fac = await client.query(`SELECT numero_factura FROM ${tF} WHERE id = $1::uuid`, [rem.rows[0].factura_id]);
    return { remision: rem.rows[0], items: items.rows, numero_factura: (fac.rows[0]?.numero_factura as string) ?? null };
  } finally {
    client.release();
  }
}
