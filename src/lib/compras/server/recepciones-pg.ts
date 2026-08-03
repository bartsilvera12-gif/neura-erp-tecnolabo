/**
 * Recepción de mercadería / Nota de recepción (Fase 2 + 5).
 *
 * Una compra puede recibirse en varias entregas parciales. El stock SOLO sube al
 * CONFIRMAR una recepción, usando el helper canónico transaccional de F0
 * (registrarMovimientoInventarioTx). La anulación repone con movimientos inversos
 * sin borrar historial. Reutiliza la tabla `compras` (modelo plano) para el
 * control comprado vs recibido; no implementa un flujo complejo de OC.
 *
 * Estados de recepción: borrador → confirmada → anulada.
 * Estado por línea de compra: registrada → parcialmente_recibida → recibida.
 */
import type { PoolClient } from "pg";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import { registrarMovimientoInventarioTx, revertirMovimientosDeDocumentoTx } from "@/lib/inventario/server/stock-core-pg";
import { getEmpresaConfigTx } from "@/lib/config/server/empresa-config-pg";
import { siguienteCorrelativoTx } from "@/lib/documentos/server/correlativo-pg";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

export class RecepcionExcedenteError extends Error {
  producto: string;
  pendiente: number;
  intentado: number;
  constructor(producto: string, pendiente: number, intentado: number) {
    super(`No se puede recibir ${intentado} de "${producto}": pendiente ${pendiente}.`);
    this.name = "RecepcionExcedenteError";
    this.producto = producto;
    this.pendiente = pendiente;
    this.intentado = intentado;
  }
}

export interface ResumenLineaCompra {
  compra_id: string;
  producto_id: string;
  producto_nombre: string;
  sku: string | null;
  cantidad: number;
  cantidad_recibida: number;
  pendiente: number;
  costo_unitario: number;
  estado: string;
}

export interface ResumenCompra {
  numero_control: string;
  proveedor_id: string | null;
  proveedor_nombre: string | null;
  moneda: string;
  estado_agregado: "registrada" | "parcialmente_recibida" | "recibida" | "cancelada";
  lineas: ResumenLineaCompra[];
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool no disponible.");
  return p;
}

/** Resumen comprado/recibido/pendiente de una compra (por numero_control). */
export async function getResumenCompra(
  schema: string,
  empresaId: string,
  numeroControl: string,
): Promise<ResumenCompra | null> {
  assertAllowedChatDataSchema(schema);
  const tC = quoteSchemaTable(schema, "compras");
  const client = await pool().connect();
  try {
    const res = await client.query(
      `SELECT id, producto_id, producto_nombre, cantidad, cantidad_recibida, costo_unitario,
              proveedor_id, proveedor_nombre, moneda, estado
         FROM ${tC}
        WHERE empresa_id = $1::uuid AND numero_control = $2 AND anulada_at IS NULL
        ORDER BY created_at`,
      [empresaId, numeroControl],
    );
    if (res.rowCount === 0) return null;
    const first = res.rows[0];
    const lineas: ResumenLineaCompra[] = res.rows.map((r) => {
      const cantidad = Number(r.cantidad) || 0;
      const recibida = Number(r.cantidad_recibida) || 0;
      return {
        compra_id: r.id,
        producto_id: r.producto_id,
        producto_nombre: r.producto_nombre,
        sku: null,
        cantidad,
        cantidad_recibida: recibida,
        pendiente: Math.max(0, cantidad - recibida),
        costo_unitario: Number(r.costo_unitario) || 0,
        estado: r.estado,
      };
    });
    const totalPend = lineas.reduce((s, l) => s + l.pendiente, 0);
    const totalRecib = lineas.reduce((s, l) => s + l.cantidad_recibida, 0);
    const anyCancel = res.rows.some((r) => r.estado === "cancelada");
    const estado_agregado = anyCancel
      ? "cancelada"
      : totalPend === 0
      ? "recibida"
      : totalRecib > 0
      ? "parcialmente_recibida"
      : "registrada";
    return {
      numero_control: numeroControl,
      proveedor_id: first.proveedor_id,
      proveedor_nombre: first.proveedor_nombre,
      moneda: first.moneda,
      estado_agregado,
      lineas,
    };
  } finally {
    client.release();
  }
}

export interface RecepcionItemInput {
  compra_id: string;
  producto_id: string;
  producto_nombre: string;
  sku?: string | null;
  cantidad_recibida: number;
  cantidad_rechazada?: number;
  costo_unitario?: number;
  observacion?: string | null;
}

export interface CrearRecepcionInput {
  compra_numero_control: string;
  deposito_id?: string | null;
  sucursal_id?: string | null;
  observacion?: string | null;
  firma_entrega?: string | null;
  firma_recepcion?: string | null;
  documento_url?: string | null;
  documento_storage_path?: string | null;
  documento_nombre?: string | null;
  documento_mime_type?: string | null;
  items: RecepcionItemInput[];
  /** Si true, confirma inmediatamente (mueve stock). Si false, queda en borrador. */
  confirmar?: boolean;
}

export interface Usuario {
  id?: string | null;
  nombre?: string | null;
  email?: string | null;
}

/** Actualiza el estado de una línea de compra según lo recibido. */
async function actualizarEstadoLineaCompra(client: PoolClient, tC: string, compraId: string, empresaId: string) {
  await client.query(
    `UPDATE ${tC}
        SET estado = CASE
              WHEN cantidad_recibida >= cantidad THEN 'recibida'
              WHEN cantidad_recibida > 0 THEN 'parcialmente_recibida'
              ELSE 'registrada' END,
            updated_at = now()
      WHERE id = $1::uuid AND empresa_id = $2::uuid`,
    [compraId, empresaId],
  );
}

/** Aplica el impacto de stock de una recepción borrador y la marca confirmada. */
async function confirmarRecepcionTx(
  client: PoolClient,
  schema: string,
  empresaId: string,
  recepcionId: string,
  usuario: Usuario,
): Promise<void> {
  const tR = quoteSchemaTable(schema, "recepciones");
  const tRI = quoteSchemaTable(schema, "recepcion_items");
  const tC = quoteSchemaTable(schema, "compras");

  const recRes = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [
    recepcionId,
    empresaId,
  ]);
  if (recRes.rowCount === 0) throw new Error("Recepción no encontrada.");
  const rec = recRes.rows[0];
  if (rec.estado !== "borrador") throw new Error(`La recepción no está en borrador (estado: ${rec.estado}).`);

  const cfg = await getEmpresaConfigTx(client, schema, empresaId);
  const items = await client.query(`SELECT * FROM ${tRI} WHERE recepcion_id = $1::uuid ORDER BY created_at`, [recepcionId]);

  for (const it of items.rows) {
    const recibida = Number(it.cantidad_recibida) || 0;
    if (recibida <= 0) continue;

    // Validar no exceder lo pendiente de la línea de compra.
    if (it.compra_id) {
      const lc = await client.query(
        `SELECT cantidad, cantidad_recibida FROM ${tC} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
        [it.compra_id, empresaId],
      );
      if ((lc.rowCount ?? 0) > 0) {
        const cantidad = Number(lc.rows[0].cantidad) || 0;
        const yaRecibida = Number(lc.rows[0].cantidad_recibida) || 0;
        const pendiente = cantidad - yaRecibida;
        if (recibida > pendiente && !cfg.permitir_excedente_recepcion) {
          throw new RecepcionExcedenteError(it.producto_nombre, pendiente, recibida);
        }
        await client.query(
          `UPDATE ${tC} SET cantidad_recibida = cantidad_recibida + $1::numeric WHERE id = $2::uuid AND empresa_id = $3::uuid`,
          [recibida, it.compra_id, empresaId],
        );
        await actualizarEstadoLineaCompra(client, tC, it.compra_id, empresaId);
      }
    }

    // ENTRADA de inventario (sube stock) vía helper canónico F0.
    await registrarMovimientoInventarioTx(client, schema, {
      empresaId,
      productoId: it.producto_id,
      productoNombre: it.producto_nombre,
      productoSku: it.sku ?? "",
      tipo: "ENTRADA",
      cantidad: recibida,
      costoUnitario: Number(it.costo_unitario) || 0,
      origen: "recepcion",
      referencia: rec.numero,
      documentoTipo: "recepcion",
      documentoId: recepcionId,
      depositoId: rec.deposito_id ?? null,
      sucursalId: rec.sucursal_id ?? null,
      observacion: it.observacion ?? null,
      usuarioId: usuario.id ?? null,
      usuarioNombre: usuario.nombre ?? null,
    });
  }

  await client.query(
    `UPDATE ${tR}
        SET estado = 'confirmada', confirmada_at = now(),
            usuario_confirmador_id = $1::uuid, usuario_confirmador_nombre = $2, updated_at = now()
      WHERE id = $3::uuid`,
    [usuario.id ?? null, usuario.nombre ?? null, recepcionId],
  );

  await registrarAuditoriaTx(client, schema, {
    empresaId,
    entidad: "recepcion",
    entidadId: recepcionId,
    accion: "confirmar",
    origen: "api/compras/recepciones",
    usuarioId: usuario.id ?? null,
    usuarioEmail: usuario.email ?? null,
    usuarioNombre: usuario.nombre ?? null,
    detalle: { numero: rec.numero, compra: rec.compra_numero_control },
  });
}

/** Crea una recepción (borrador o confirmada) en una sola transacción. */
export async function crearRecepcion(
  schema: string,
  empresaId: string,
  input: CrearRecepcionInput,
  usuario: Usuario,
): Promise<{ recepcion_id: string; numero: string; confirmada: boolean }> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "recepciones");
  const tRI = quoteSchemaTable(schema, "recepcion_items");
  const tC = quoteSchemaTable(schema, "compras");

  if (!input.items || input.items.length === 0) throw new Error("La recepción no tiene ítems.");

  const client = await pool().connect();
  try {
    await client.query("BEGIN");

    // Proveedor de la compra (para snapshot).
    const provRes = await client.query(
      `SELECT proveedor_id, proveedor_nombre FROM ${tC} WHERE empresa_id = $1::uuid AND numero_control = $2 LIMIT 1`,
      [empresaId, input.compra_numero_control],
    );
    if (provRes.rowCount === 0) throw new Error("Compra no encontrada.");

    const { numero } = await siguienteCorrelativoTx(client, schema, empresaId, "recepcion", { prefijo: "NR" });

    const recRes = await client.query(
      `INSERT INTO ${tR} (
         empresa_id, numero, compra_numero_control, proveedor_id, proveedor_nombre,
         deposito_id, sucursal_id, observacion, estado,
         firma_entrega, firma_recepcion,
         documento_url, documento_storage_path, documento_nombre, documento_mime_type,
         usuario_creador_id, usuario_creador_nombre
       ) VALUES (
         $1::uuid, $2, $3, $4::uuid, $5,
         $6::uuid, $7::uuid, $8, 'borrador',
         $9, $10,
         $11, $12, $13, $14,
         $15::uuid, $16
       ) RETURNING id`,
      [
        empresaId, numero, input.compra_numero_control,
        provRes.rows[0].proveedor_id, provRes.rows[0].proveedor_nombre,
        input.deposito_id ?? null, input.sucursal_id ?? null, input.observacion ?? null,
        input.firma_entrega ?? null, input.firma_recepcion ?? null,
        input.documento_url ?? null, input.documento_storage_path ?? null,
        input.documento_nombre ?? null, input.documento_mime_type ?? null,
        usuario.id ?? null, usuario.nombre ?? null,
      ],
    );
    const recepcionId = recRes.rows[0].id as string;

    for (const it of input.items) {
      await client.query(
        `INSERT INTO ${tRI} (
           empresa_id, recepcion_id, compra_id, producto_id, producto_nombre, sku,
           cantidad_recibida, cantidad_rechazada, costo_unitario, observacion
         ) VALUES (
           $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5, $6,
           $7::numeric, $8::numeric, $9::numeric, $10
         )`,
        [
          empresaId, recepcionId, it.compra_id ?? null, it.producto_id, it.producto_nombre, it.sku ?? null,
          Number(it.cantidad_recibida) || 0, Number(it.cantidad_rechazada) || 0,
          Number(it.costo_unitario) || 0, it.observacion ?? null,
        ],
      );
    }

    if (input.confirmar) {
      await confirmarRecepcionTx(client, schema, empresaId, recepcionId, usuario);
    }

    await client.query("COMMIT");
    return { recepcion_id: recepcionId, numero, confirmada: !!input.confirmar };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

/** Confirma una recepción en borrador (mueve stock). */
export async function confirmarRecepcion(
  schema: string,
  empresaId: string,
  recepcionId: string,
  usuario: Usuario,
): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    await confirmarRecepcionTx(client, schema, empresaId, recepcionId, usuario);
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

/** Anula una recepción confirmada: repone stock con movimientos inversos. */
export async function anularRecepcion(
  schema: string,
  empresaId: string,
  recepcionId: string,
  usuario: Usuario,
  motivo: string,
): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "recepciones");
  const tRI = quoteSchemaTable(schema, "recepcion_items");
  const tC = quoteSchemaTable(schema, "compras");
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const recRes = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [
      recepcionId,
      empresaId,
    ]);
    if (recRes.rowCount === 0) throw new Error("Recepción no encontrada.");
    const rec = recRes.rows[0];
    if (rec.estado !== "confirmada") throw new Error(`Solo se anula una recepción confirmada (estado: ${rec.estado}).`);

    // Revertir stock (movimientos inversos, sin borrar historial).
    await revertirMovimientosDeDocumentoTx(client, schema, {
      empresaId,
      documentoTipo: "recepcion",
      documentoId: recepcionId,
      usuarioId: usuario.id ?? null,
      usuarioNombre: usuario.nombre ?? null,
      motivo: `Anulación recepción ${rec.numero}: ${motivo}`,
    });

    // Descontar lo recibido de las líneas de compra y recalcular estados.
    const items = await client.query(`SELECT compra_id, cantidad_recibida FROM ${tRI} WHERE recepcion_id = $1::uuid`, [
      recepcionId,
    ]);
    for (const it of items.rows) {
      if (!it.compra_id) continue;
      await client.query(
        `UPDATE ${tC} SET cantidad_recibida = GREATEST(0, cantidad_recibida - $1::numeric) WHERE id = $2::uuid AND empresa_id = $3::uuid`,
        [Number(it.cantidad_recibida) || 0, it.compra_id, empresaId],
      );
      await actualizarEstadoLineaCompra(client, tC, it.compra_id, empresaId);
    }

    await client.query(
      `UPDATE ${tR} SET estado = 'anulada', anulada_at = now(), anulada_por = $1::uuid, anulada_motivo = $2, updated_at = now() WHERE id = $3::uuid`,
      [usuario.id ?? null, motivo, recepcionId],
    );

    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "recepcion",
      entidadId: recepcionId,
      accion: "anular",
      origen: "api/compras/recepciones",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { numero: rec.numero, motivo },
    });

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export interface RecepcionResumenRow {
  id: string;
  numero: string;
  compra_numero_control: string;
  estado: string;
  fecha: string;
  proveedor_nombre: string | null;
  total_recibido: number;
}

/** Lista recepciones (opcionalmente de una compra). */
export async function listRecepciones(
  schema: string,
  empresaId: string,
  numeroControl?: string,
): Promise<RecepcionResumenRow[]> {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "recepciones");
  const tRI = quoteSchemaTable(schema, "recepcion_items");
  const pool0 = getChatPostgresPool();
  if (!pool0) throw new Error("Pool no disponible.");
  const where: string[] = ["r.empresa_id = $1::uuid"];
  const vals: unknown[] = [empresaId];
  if (numeroControl) {
    vals.push(numeroControl);
    where.push(`r.compra_numero_control = $${vals.length}`);
  }
  const client = await pool0.connect();
  try {
    const res = await client.query(
      `SELECT r.id, r.numero, r.compra_numero_control, r.estado, r.fecha, r.proveedor_nombre,
              COALESCE((SELECT SUM(cantidad_recibida) FROM ${tRI} ri WHERE ri.recepcion_id = r.id), 0) AS total_recibido
         FROM ${tR} r
        WHERE ${where.join(" AND ")}
        ORDER BY r.created_at DESC`,
      vals,
    );
    return res.rows as RecepcionResumenRow[];
  } finally {
    client.release();
  }
}

/** Detalle completo de una recepción (para PDF/impresión). */
export async function getRecepcion(schema: string, empresaId: string, recepcionId: string) {
  assertAllowedChatDataSchema(schema);
  const tR = quoteSchemaTable(schema, "recepciones");
  const tRI = quoteSchemaTable(schema, "recepcion_items");
  const pool0 = getChatPostgresPool();
  if (!pool0) throw new Error("Pool no disponible.");
  const client = await pool0.connect();
  try {
    const rec = await client.query(`SELECT * FROM ${tR} WHERE id = $1::uuid AND empresa_id = $2::uuid`, [recepcionId, empresaId]);
    if (rec.rowCount === 0) return null;
    const items = await client.query(`SELECT * FROM ${tRI} WHERE recepcion_id = $1::uuid ORDER BY created_at`, [recepcionId]);
    return { recepcion: rec.rows[0], items: items.rows };
  } finally {
    client.release();
  }
}
