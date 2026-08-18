/**
 * Notas de remisión sobre VENTAS — entregas parciales del flujo POS.
 *
 * Diferencia clave con `remisiones-pg.ts` (rama facturas): acá el stock NO se
 * mueve. En el flujo POS el inventario ya salió al registrar la venta (movimiento
 * origen 'venta'), así que la remisión es un registro de ENTREGA: qué se le dio
 * físicamente al cliente y qué queda pendiente.
 *
 * Varias remisiones por venta. Nunca se puede entregar más de lo vendido.
 * Editar una remisión ajusta `ventas_items.cantidad_entregada` por la diferencia.
 * Anular devuelve lo entregado al pendiente.
 */
import type { PoolClient } from "pg";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import { siguienteCorrelativoTx } from "@/lib/documentos/server/correlativo-pg";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

/** Se intenta entregar más de lo que queda pendiente de un ítem. */
export class RemisionVentaExcedenteError extends Error {
  producto: string;
  disponible: number;
  intentado: number;
  constructor(producto: string, disponible: number, intentado: number) {
    super(`No se puede remitir ${intentado} de "${producto}": quedan ${disponible} por entregar.`);
    this.name = "RemisionVentaExcedenteError";
    this.producto = producto;
    this.disponible = disponible;
    this.intentado = intentado;
  }
}

export interface LineaEntregaVenta {
  venta_item_id: string;
  producto_id: string;
  producto_nombre: string;
  sku: string | null;
  cantidad_vendida: number;
  cantidad_entregada: number;
  /** Lo que todavía falta entregar. */
  pendiente: number;
}

export interface ResumenVentaEntrega {
  venta_id: string;
  numero_control: string;
  estado_entrega: string;
  cliente_nombre: string | null;
  numero_orden_compra: string | null;
  lineas: LineaEntregaVenta[];
}

export interface Usuario {
  id?: string | null;
  nombre?: string | null;
  email?: string | null;
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

/** Recalcula `ventas.estado_entrega` a partir de lo entregado por ítem. */
async function recomputarEstadoEntregaVenta(
  client: PoolClient,
  schema: string,
  empresaId: string,
  ventaId: string,
) {
  const tV = quoteSchemaTable(schema, "ventas");
  const tVI = quoteSchemaTable(schema, "ventas_items");
  const agg = await client.query(
    `SELECT COALESCE(SUM(cantidad),0)::numeric AS vend, COALESCE(SUM(cantidad_entregada),0)::numeric AS entr
       FROM ${tVI} WHERE venta_id = $1::uuid AND empresa_id = $2::uuid`,
    [ventaId, empresaId],
  );
  const vend = num(agg.rows[0].vend);
  const entr = num(agg.rows[0].entr);
  const estado = entr <= 0 ? "pendiente" : entr >= vend ? "entregada" : "parcialmente_entregada";
  await client.query(
    `UPDATE ${tV} SET estado_entrega = $1, updated_at = now() WHERE id = $2::uuid AND empresa_id = $3::uuid`,
    [estado, ventaId, empresaId],
  );
}

/** Resumen vendido/entregado/pendiente por ítem de una venta. */
export async function getResumenVentaEntrega(
  schema: string,
  empresaId: string,
  ventaId: string,
): Promise<ResumenVentaEntrega | null> {
  assertAllowedChatDataSchema(schema);
  const tV = quoteSchemaTable(schema, "ventas");
  const tVI = quoteSchemaTable(schema, "ventas_items");
  const tC = quoteSchemaTable(schema, "clientes");
  const client = await pool().connect();
  try {
    const v = await client.query(
      `SELECT v.id, v.numero_control, v.estado_entrega, v.numero_orden_compra,
              COALESCE(c.empresa, c.nombre_contacto, c.nombre) AS cliente_nombre
         FROM ${tV} v
         LEFT JOIN ${tC} c ON c.id = v.cliente_id
        WHERE v.id = $1::uuid AND v.empresa_id = $2::uuid`,
      [ventaId, empresaId],
    );
    if (v.rowCount === 0) return null;

    const items = await client.query(
      `SELECT id, producto_id, producto_nombre, sku,
              COALESCE(cantidad,0)::numeric AS cantidad,
              COALESCE(cantidad_entregada,0)::numeric AS cantidad_entregada
         FROM ${tVI}
        WHERE venta_id = $1::uuid AND empresa_id = $2::uuid
        ORDER BY created_at`,
      [ventaId, empresaId],
    );

    const lineas: LineaEntregaVenta[] = items.rows.map((r) => {
      const vendida = num(r.cantidad);
      const entregada = num(r.cantidad_entregada);
      return {
        venta_item_id: r.id as string,
        producto_id: r.producto_id as string,
        producto_nombre: r.producto_nombre as string,
        sku: (r.sku as string) ?? null,
        cantidad_vendida: vendida,
        cantidad_entregada: entregada,
        pendiente: Math.max(0, vendida - entregada),
      };
    });

    return {
      venta_id: ventaId,
      numero_control: v.rows[0].numero_control as string,
      estado_entrega: v.rows[0].estado_entrega as string,
      cliente_nombre: (v.rows[0].cliente_nombre as string) ?? null,
      numero_orden_compra: (v.rows[0].numero_orden_compra as string) ?? null,
      lineas,
    };
  } finally {
    client.release();
  }
}

export interface RemisionVentaItemInput {
  venta_item_id: string;
  cantidad: number;
  observacion?: string | null;
}

export interface CrearRemisionVentaInput {
  venta_id: string;
  observacion?: string | null;
  items: RemisionVentaItemInput[];
}

/**
 * Aplica las cantidades de una remisión sobre `ventas_items.cantidad_entregada`.
 * `signo` = +1 al entregar, -1 al revertir. Valida el tope contra lo vendido.
 */
async function aplicarEntregaTx(
  client: PoolClient,
  schema: string,
  empresaId: string,
  items: Array<{ venta_item_id: string | null; cantidad: number; producto_nombre: string }>,
  signo: 1 | -1,
) {
  const tVI = quoteSchemaTable(schema, "ventas_items");
  for (const it of items) {
    if (!it.venta_item_id) continue;
    const delta = num(it.cantidad) * signo;
    if (delta === 0) continue;

    const fi = await client.query(
      `SELECT COALESCE(cantidad,0)::numeric AS cant, COALESCE(cantidad_entregada,0)::numeric AS entr
         FROM ${tVI} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [it.venta_item_id, empresaId],
    );
    if ((fi.rowCount ?? 0) === 0) continue;

    const vendida = num(fi.rows[0].cant);
    const entregada = num(fi.rows[0].entr);
    const nueva = entregada + delta;
    if (nueva > vendida) {
      throw new RemisionVentaExcedenteError(it.producto_nombre, Math.max(0, vendida - entregada), num(it.cantidad));
    }
    await client.query(
      `UPDATE ${tVI} SET cantidad_entregada = $1::numeric WHERE id = $2::uuid`,
      [Math.max(0, nueva), it.venta_item_id],
    );
  }
}

/** Crea una remisión de venta ya entregada (no hay estado borrador acá). */
export async function crearRemisionVenta(
  schema: string,
  empresaId: string,
  input: CrearRemisionVentaInput,
  usuario: Usuario,
): Promise<{ remision_id: string; numero: string }> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const tV = quoteSchemaTable(schema, "ventas");
  const tVI = quoteSchemaTable(schema, "ventas_items");

  const conCantidad = (input.items ?? []).filter((i) => num(i.cantidad) > 0);
  if (conCantidad.length === 0) throw new Error("Indicá al menos una cantidad a entregar.");

  const client = await pool().connect();
  try {
    await client.query("BEGIN");

    const v = await client.query(
      `SELECT cliente_id FROM ${tV} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [input.venta_id, empresaId],
    );
    if (v.rowCount === 0) throw new Error("Venta no encontrada.");

    // Datos de los ítems de venta involucrados (nombre/sku para el snapshot).
    const ids = conCantidad.map((i) => i.venta_item_id);
    const vi = await client.query(
      `SELECT id, producto_id, producto_nombre, sku FROM ${tVI}
        WHERE venta_id = $1::uuid AND empresa_id = $2::uuid AND id = ANY($3::uuid[])`,
      [input.venta_id, empresaId, ids],
    );
    const porId = new Map<string, Record<string, unknown>>();
    for (const r of vi.rows) porId.set(String(r.id), r);

    const { numero } = await siguienteCorrelativoTx(client, schema, empresaId, "remision_venta", { prefijo: "NR" });

    const rem = await client.query(
      `INSERT INTO ${tR} (
         empresa_id, numero, venta_id, cliente_id, observacion, estado,
         usuario_creador_id, usuario_creador_nombre, confirmada_at,
         usuario_confirmador_id, usuario_confirmador_nombre
       ) VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $5, 'confirmada', $6::uuid, $7, now(), $6::uuid, $7)
       RETURNING id`,
      [
        empresaId,
        numero,
        input.venta_id,
        v.rows[0].cliente_id ?? null,
        input.observacion ?? null,
        usuario.id ?? null,
        usuario.nombre ?? null,
      ],
    );
    const remisionId = rem.rows[0].id as string;

    const paraAplicar: Array<{ venta_item_id: string | null; cantidad: number; producto_nombre: string }> = [];
    for (const it of conCantidad) {
      const base = porId.get(it.venta_item_id);
      if (!base) throw new Error("Un ítem indicado no pertenece a esta venta.");
      await client.query(
        `INSERT INTO ${tRI} (empresa_id, remision_id, venta_item_id, producto_id, producto_nombre, sku, cantidad, costo_unitario, observacion)
           VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5, $6, $7::numeric, 0, $8)`,
        [
          empresaId,
          remisionId,
          it.venta_item_id,
          base.producto_id,
          base.producto_nombre,
          base.sku ?? null,
          num(it.cantidad),
          it.observacion ?? null,
        ],
      );
      paraAplicar.push({
        venta_item_id: it.venta_item_id,
        cantidad: num(it.cantidad),
        producto_nombre: String(base.producto_nombre ?? ""),
      });
    }

    await aplicarEntregaTx(client, schema, empresaId, paraAplicar, 1);
    await recomputarEstadoEntregaVenta(client, schema, empresaId, input.venta_id);

    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "remision_venta",
      entidadId: remisionId,
      accion: "crear",
      origen: "api/ventas/remisiones",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { numero, venta_id: input.venta_id, items: paraAplicar.length },
    });

    await client.query("COMMIT");
    return { remision_id: remisionId, numero };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

/**
 * Edita las cantidades entregadas de una remisión existente. Ajusta
 * `cantidad_entregada` por la DIFERENCIA, no por el total, para no descuadrar
 * lo entregado por otras remisiones de la misma venta.
 */
export async function editarRemisionVenta(
  schema: string,
  empresaId: string,
  remisionId: string,
  items: RemisionVentaItemInput[],
  observacion: string | null | undefined,
  usuario: Usuario,
): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const tVI = quoteSchemaTable(schema, "ventas_items");

  const client = await pool().connect();
  try {
    await client.query("BEGIN");

    const rem = await client.query(
      `SELECT id, venta_id, estado FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [remisionId, empresaId],
    );
    if (rem.rowCount === 0) throw new Error("Remisión no encontrada.");
    const ventaId = rem.rows[0].venta_id as string | null;
    if (!ventaId) throw new Error("Esta remisión no pertenece a una venta.");
    if (rem.rows[0].estado === "anulada") throw new Error("La remisión está anulada; no se puede editar.");

    // Revertir lo que esta remisión tenía cargado.
    const previos = await client.query(
      `SELECT venta_item_id, cantidad, producto_nombre FROM ${tRI} WHERE remision_id = $1::uuid`,
      [remisionId],
    );
    await aplicarEntregaTx(
      client,
      schema,
      empresaId,
      previos.rows.map((r) => ({
        venta_item_id: (r.venta_item_id as string) ?? null,
        cantidad: num(r.cantidad),
        producto_nombre: String(r.producto_nombre ?? ""),
      })),
      -1,
    );
    await client.query(`DELETE FROM ${tRI} WHERE remision_id = $1::uuid`, [remisionId]);

    // Insertar las nuevas líneas y aplicarlas.
    const conCantidad = (items ?? []).filter((i) => num(i.cantidad) > 0);
    const ids = conCantidad.map((i) => i.venta_item_id);
    const vi = ids.length
      ? await client.query(
          `SELECT id, producto_id, producto_nombre, sku FROM ${tVI}
            WHERE venta_id = $1::uuid AND empresa_id = $2::uuid AND id = ANY($3::uuid[])`,
          [ventaId, empresaId, ids],
        )
      : { rows: [] as Record<string, unknown>[] };
    const porId = new Map<string, Record<string, unknown>>();
    for (const r of vi.rows) porId.set(String(r.id), r);

    const paraAplicar: Array<{ venta_item_id: string | null; cantidad: number; producto_nombre: string }> = [];
    for (const it of conCantidad) {
      const base = porId.get(it.venta_item_id);
      if (!base) throw new Error("Un ítem indicado no pertenece a esta venta.");
      await client.query(
        `INSERT INTO ${tRI} (empresa_id, remision_id, venta_item_id, producto_id, producto_nombre, sku, cantidad, costo_unitario, observacion)
           VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5, $6, $7::numeric, 0, $8)`,
        [
          empresaId,
          remisionId,
          it.venta_item_id,
          base.producto_id,
          base.producto_nombre,
          base.sku ?? null,
          num(it.cantidad),
          it.observacion ?? null,
        ],
      );
      paraAplicar.push({
        venta_item_id: it.venta_item_id,
        cantidad: num(it.cantidad),
        producto_nombre: String(base.producto_nombre ?? ""),
      });
    }
    await aplicarEntregaTx(client, schema, empresaId, paraAplicar, 1);

    if (observacion !== undefined) {
      await client.query(`UPDATE ${tR} SET observacion = $1, updated_at = now() WHERE id = $2::uuid`, [
        observacion ?? null,
        remisionId,
      ]);
    }

    await recomputarEstadoEntregaVenta(client, schema, empresaId, ventaId);
    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "remision_venta",
      entidadId: remisionId,
      accion: "editar",
      origen: "api/ventas/remisiones",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { venta_id: ventaId, items: paraAplicar.length },
    });

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

/** Anula la remisión y devuelve lo entregado al pendiente. */
export async function anularRemisionVenta(
  schema: string,
  empresaId: string,
  remisionId: string,
  motivo: string | null,
  usuario: Usuario,
): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");

  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const rem = await client.query(
      `SELECT id, venta_id, estado FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [remisionId, empresaId],
    );
    if (rem.rowCount === 0) throw new Error("Remisión no encontrada.");
    if (rem.rows[0].estado === "anulada") {
      await client.query("COMMIT");
      return; // idempotente
    }
    const ventaId = rem.rows[0].venta_id as string | null;
    if (!ventaId) throw new Error("Esta remisión no pertenece a una venta.");

    const previos = await client.query(
      `SELECT venta_item_id, cantidad, producto_nombre FROM ${tRI} WHERE remision_id = $1::uuid`,
      [remisionId],
    );
    await aplicarEntregaTx(
      client,
      schema,
      empresaId,
      previos.rows.map((r) => ({
        venta_item_id: (r.venta_item_id as string) ?? null,
        cantidad: num(r.cantidad),
        producto_nombre: String(r.producto_nombre ?? ""),
      })),
      -1,
    );

    await client.query(
      `UPDATE ${tR} SET estado = 'anulada', anulada_at = now(), anulada_por = $2::uuid, anulada_motivo = $3, updated_at = now()
        WHERE id = $1::uuid`,
      [remisionId, usuario.id ?? null, motivo ?? null],
    );

    await recomputarEstadoEntregaVenta(client, schema, empresaId, ventaId);
    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "remision_venta",
      entidadId: remisionId,
      accion: "anular",
      origen: "api/ventas/remisiones",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { venta_id: ventaId, motivo },
    });

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

/** Lista las remisiones de una venta. */
export async function listarRemisionesVenta(schema: string, empresaId: string, ventaId: string) {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const client = await pool().connect();
  try {
    const r = await client.query(
      `SELECT r.id, r.numero, r.estado, r.fecha, r.observacion,
              COALESCE((SELECT count(*) FROM ${tRI} i WHERE i.remision_id = r.id), 0)::int AS total_items
         FROM ${tR} r
        WHERE r.venta_id = $1::uuid AND r.empresa_id = $2::uuid
        ORDER BY r.fecha DESC`,
      [ventaId, empresaId],
    );
    return r.rows;
  } finally {
    client.release();
  }
}

/** Detalle de una remisión de venta, con el tope editable por ítem. */
export async function getRemisionVentaParaEdicion(schema: string, empresaId: string, remisionId: string) {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "notas_remision");
  const tRI = quoteSchemaTable(schema, "notas_remision_items");
  const client = await pool().connect();
  try {
    const remQ = await client.query(
      `SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid`,
      [remisionId, empresaId],
    );
    if (remQ.rowCount === 0) return null;
    const rem = remQ.rows[0];
    if (!rem.venta_id) return null;

    const itemsQ = await client.query(
      `SELECT venta_item_id, cantidad, observacion FROM ${tRI} WHERE remision_id = $1::uuid`,
      [remisionId],
    );
    const enEsta = new Map<string, { cantidad: number; observacion: string | null }>();
    for (const it of itemsQ.rows) {
      if (it.venta_item_id) {
        enEsta.set(String(it.venta_item_id), {
          cantidad: num(it.cantidad),
          observacion: (it.observacion as string) ?? null,
        });
      }
    }

    const resumen = await getResumenVentaEntrega(schema, empresaId, String(rem.venta_id));
    if (!resumen) return null;

    const anulada = rem.estado === "anulada";
    const lineas = resumen.lineas.map((l) => {
      const e = enEsta.get(l.venta_item_id);
      const enEstaCant = e?.cantidad ?? 0;
      // `cantidad_entregada` ya incluye esta remisión (salvo que esté anulada).
      const entregadoOtras = anulada ? l.cantidad_entregada : Math.max(0, l.cantidad_entregada - enEstaCant);
      return {
        ...l,
        en_esta_remision: enEstaCant,
        entregado_otras: entregadoOtras,
        max_a_entregar: Math.max(0, l.cantidad_vendida - entregadoOtras),
        observacion: e?.observacion ?? null,
      };
    });

    return {
      remision: {
        id: rem.id as string,
        numero: rem.numero as string,
        estado: rem.estado as string,
        fecha: rem.fecha,
        venta_id: String(rem.venta_id),
        numero_control: resumen.numero_control,
        numero_orden_compra: resumen.numero_orden_compra,
        cliente_nombre: rem.cliente_nombre ?? resumen.cliente_nombre ?? null,
        observacion: (rem.observacion as string) ?? null,
        usuario_creador_nombre: (rem.usuario_creador_nombre as string) ?? null,
        anulada_motivo: (rem.anulada_motivo as string) ?? null,
      },
      lineas,
    };
  } finally {
    client.release();
  }
}
