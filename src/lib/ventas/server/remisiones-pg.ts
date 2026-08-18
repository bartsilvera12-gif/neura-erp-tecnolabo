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
  /** N.º de Orden de Compra del cliente (heredado del presupuesto o cargado en la factura). */
  numero_orden_compra: string | null;
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
    const fac = await client.query(
      `SELECT id, numero_factura, estado_entrega, numero_orden_compra FROM ${tF} WHERE id = $1::uuid AND empresa_id = $2::uuid`,
      [facturaId, empresaId],
    );
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
      numero_orden_compra: (fac.rows[0].numero_orden_compra as string | null) ?? null,
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
    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "remision",
      entidadId: remisionId,
      accion: "crear",
      origen: "api/remisiones",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { numero, factura_id: input.factura_id, items: input.items.length, confirmada: !!input.confirmar },
    });
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
    const fac = await client.query(`SELECT numero_factura, numero_orden_compra FROM ${tF} WHERE id = $1::uuid`, [rem.rows[0].factura_id]);
    return {
      remision: rem.rows[0],
      items: items.rows,
      numero_factura: (fac.rows[0]?.numero_factura as string) ?? null,
      // Se lee en vivo desde la factura (no se congela en la remisión): si la OC se
      // corrige en la factura, las remisiones ya emitidas siguen coherentes.
      numero_orden_compra: (fac.rows[0]?.numero_orden_compra as string | null) ?? null,
    };
  } finally {
    client.release();
  }
}

export interface LineaEdicionRemision extends LineaEntrega {
  /** Cantidad que esta remisión entrega hoy de este ítem. */
  en_esta_remision: number;
  /** Entregado por OTRAS remisiones confirmadas (no cuenta ésta). */
  entregado_otras: number;
  /** Tope editable para este ítem en esta remisión = facturado - entregado_otras. */
  max_a_entregar: number;
  observacion: string | null;
}

/**
 * Detalle de una remisión listo para VER o EDITAR: cabecera + una línea por cada
 * ítem de la factura con el tope editable correcto según el estado de la remisión
 * (para confirmada, la cantidad ya entregada por esta remisión se descuenta del
 * "entregado por otras" para poder subir/bajar sin falsos topes).
 */
export async function getRemisionParaEdicion(schema: string, empresaId: string, remisionId: string) {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const client = await pool().connect();
  try {
    const remQ = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid`, [remisionId, empresaId]);
    if (remQ.rowCount === 0) return null;
    const rem = remQ.rows[0];
    const itemsQ = await client.query(`SELECT factura_item_id, cantidad, observacion FROM ${tRI} WHERE remision_id = $1::uuid`, [remisionId]);
    const enEsta = new Map<string, { cantidad: number; observacion: string | null }>();
    for (const it of itemsQ.rows) if (it.factura_item_id) enEsta.set(it.factura_item_id as string, { cantidad: Number(it.cantidad) || 0, observacion: it.observacion ?? null });

    const resumen = await getResumenFacturaEntrega(schema, empresaId, rem.factura_id);
    if (!resumen) return null;
    const esConfirmada = rem.estado === "confirmada";
    const lineas: LineaEdicionRemision[] = resumen.lineas.map((l) => {
      const e = enEsta.get(l.factura_item_id);
      const cantEnEsta = e?.cantidad ?? 0;
      // Para confirmada, cantidad_entregada YA incluye esta remisión → descontarla.
      // Para borrador, esta remisión aún no suma a cantidad_entregada.
      const entregadoOtras = esConfirmada ? Math.max(0, l.cantidad_entregada - cantEnEsta) : l.cantidad_entregada;
      return {
        ...l,
        en_esta_remision: cantEnEsta,
        entregado_otras: entregadoOtras,
        max_a_entregar: Math.max(0, l.cantidad_facturada - entregadoOtras),
        observacion: e?.observacion ?? null,
      };
    });
    return {
      remision: {
        id: rem.id as string,
        numero: rem.numero as string,
        estado: rem.estado as string,
        fecha: rem.fecha,
        factura_id: rem.factura_id as string,
        numero_factura: resumen.numero_factura,
        numero_orden_compra: resumen.numero_orden_compra,
        cliente_nombre: rem.cliente_nombre ?? null,
        observacion: rem.observacion ?? null,
        usuario_creador_nombre: rem.usuario_creador_nombre ?? null,
        usuario_confirmador_nombre: rem.usuario_confirmador_nombre ?? null,
        confirmada_at: rem.confirmada_at ?? null,
      },
      lineas,
    };
  } finally {
    client.release();
  }
}

export interface EditarRemisionInput {
  items: RemisionItemInput[];
  observacion?: string | null;
}

/**
 * Edita una remisión (borrador o confirmada). NO toca la factura.
 *  - Borrador: reemplaza ítems/cantidades validando no superar lo disponible.
 *    No mueve stock (el borrador aún no descontó).
 *  - Confirmada: aplica SOLO la diferencia por ítem — ajusta stock (SALIDA si sube,
 *    ENTRADA si baja), actualiza factura_items.cantidad_entregada por el delta y
 *    recomputa el estado de entrega. No regenera el movimiento completo.
 * Anulada: no editable. Registra auditoría con el detalle de cambios.
 */
export async function editarRemision(schema: string, empresaId: string, remisionId: string, input: EditarRemisionInput, usuario: Usuario): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const tFI = quoteSchemaTable(schema, "factura_items");
  const EPS = 1e-9;

  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const remQ = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [remisionId, empresaId]);
    if (remQ.rowCount === 0) throw new Error("Remisión no encontrada.");
    const rem = remQ.rows[0];
    if (rem.estado === "anulada") throw new Error("No se puede editar una remisión anulada.");
    const esConfirmada = rem.estado === "confirmada";

    // Nuevas cantidades por factura_item_id (solo ítems de factura, cantidad > 0).
    const nuevos = new Map<string, RemisionItemInput>();
    for (const it of input.items) {
      if (!it.factura_item_id) continue;
      if ((Number(it.cantidad) || 0) > 0) nuevos.set(it.factura_item_id, it);
    }
    if (nuevos.size === 0) throw new Error("La remisión debe tener al menos un ítem con cantidad mayor a 0.");

    // Ítems actuales de la remisión.
    const actualesQ = await client.query(`SELECT * FROM ${tRI} WHERE remision_id = $1::uuid`, [remisionId]);
    const actuales = new Map<string, Record<string, unknown>>();
    for (const it of actualesQ.rows) if (it.factura_item_id) actuales.set(it.factura_item_id as string, it);

    const cfg = await getEmpresaConfigTx(client, schema, empresaId);
    const cambios: Array<{ producto: string; de: number; a: number }> = [];
    const ids = new Set<string>([...actuales.keys(), ...nuevos.keys()]);

    for (const fiId of ids) {
      const viejo = actuales.get(fiId);
      const nuevo = nuevos.get(fiId);
      const cantVieja = viejo ? Number(viejo.cantidad) || 0 : 0;
      const cantNueva = nuevo ? Number(nuevo.cantidad) || 0 : 0;
      const delta = cantNueva - cantVieja;
      const prodId = (nuevo?.producto_id ?? viejo?.producto_id) as string;
      const prodNombre = (nuevo?.producto_nombre ?? viejo?.producto_nombre) as string;
      const sku = (nuevo?.sku ?? (viejo?.sku as string | null) ?? null) as string | null;
      const costo = Number(nuevo?.costo_unitario ?? viejo?.costo_unitario ?? 0);

      // Validación de tope según estado, con lock del ítem de factura.
      const fiQ = await client.query(
        `SELECT COALESCE(cantidad,0)::numeric AS cant, COALESCE(cantidad_entregada,0)::numeric AS entr
           FROM ${tFI} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
        [fiId, empresaId],
      );
      if ((fiQ.rowCount ?? 0) > 0) {
        const facturada = Number(fiQ.rows[0].cant);
        const entregadaTotal = Number(fiQ.rows[0].entr);
        // Confirmada: entregadaTotal incluye cantVieja. Borrador: no la incluye.
        const entregadoOtras = esConfirmada ? entregadaTotal - cantVieja : entregadaTotal;
        const maxPermitido = facturada - entregadoOtras;
        if (cantNueva > maxPermitido + EPS) throw new RemisionExcedenteError(prodNombre, Math.max(0, maxPermitido), cantNueva);

        // Confirmada: aplicar SOLO la diferencia (stock + cantidad_entregada).
        if (esConfirmada && Math.abs(delta) > EPS) {
          await client.query(`UPDATE ${tFI} SET cantidad_entregada = GREATEST(0, cantidad_entregada + $1::numeric) WHERE id = $2::uuid AND empresa_id = $3::uuid`, [delta, fiId, empresaId]);
          await registrarMovimientoInventarioTx(
            client,
            schema,
            {
              empresaId,
              productoId: prodId,
              productoNombre: prodNombre,
              productoSku: sku ?? "",
              tipo: delta > 0 ? "SALIDA" : "ENTRADA",
              cantidad: Math.abs(delta),
              costoUnitario: costo,
              origen: "remision",
              referencia: rem.numero,
              documentoTipo: "remision",
              documentoId: remisionId,
              depositoId: rem.deposito_id ?? null,
              sucursalId: rem.sucursal_id ?? null,
              observacion: `Ajuste por edición de remisión (${cantVieja} → ${cantNueva})`,
              usuarioId: usuario.id ?? null,
              usuarioNombre: usuario.nombre ?? null,
            },
            { permitirStockNegativo: cfg.permitir_stock_negativo, onInsuficiente: "throw" },
          );
        }
      }

      // Reflejar en los ítems de la remisión.
      if (cantNueva <= 0 && viejo) {
        await client.query(`DELETE FROM ${tRI} WHERE id = $1::uuid`, [viejo.id]);
      } else if (viejo) {
        await client.query(`UPDATE ${tRI} SET cantidad = $1::numeric WHERE id = $2::uuid`, [cantNueva, viejo.id]);
      } else if (cantNueva > 0) {
        await client.query(
          `INSERT INTO ${tRI} (empresa_id, remision_id, factura_item_id, producto_id, producto_nombre, sku, cantidad, costo_unitario, observacion)
             VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5, $6, $7::numeric, $8::numeric, $9)`,
          [empresaId, remisionId, fiId, prodId, prodNombre, sku, cantNueva, costo, null],
        );
      }
      if (Math.abs(delta) > EPS) cambios.push({ producto: prodNombre, de: cantVieja, a: cantNueva });
    }

    await client.query(`UPDATE ${tR} SET observacion = $1, updated_at = now() WHERE id = $2::uuid AND empresa_id = $3::uuid`, [input.observacion ?? rem.observacion ?? null, remisionId, empresaId]);
    if (esConfirmada) await recomputarEstadoEntregaFactura(client, schema, empresaId, rem.factura_id);

    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "remision",
      entidadId: remisionId,
      accion: "editar",
      origen: "api/remisiones",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { numero: rem.numero, factura_id: rem.factura_id, estado: rem.estado, cambios },
    });

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}
