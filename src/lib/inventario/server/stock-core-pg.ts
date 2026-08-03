/**
 * Núcleo transaccional de inventario (Fase 0).
 *
 * Helper canónico para registrar movimientos de inventario y actualizar stock
 * de forma atómica DENTRO de la transacción del caller (recibe un PoolClient).
 * Todas las nuevas operaciones (recepción, nota de salida, remisión, ajustes,
 * transferencias) deben usar esto en lugar de duplicar `UPDATE productos ...`.
 *
 * Reglas:
 *  - El movimiento SIEMPRE registra la cantidad real (positiva). El signo lo
 *    determina `tipo` (ENTRADA suma, SALIDA resta, AJUSTE usa el signo de la
 *    cantidad con signo pasado en `cantidadConSigno`).
 *  - Nunca hay cambios silenciosos de stock: cada delta deja su fila en el ledger.
 *  - `puede_acceder_empresa` / RLS siguen aplicando a nivel PostgREST; aquí se
 *    usa el pool service-role, por lo que el caller ya validó empresa/permisos.
 *
 * Patrón de identificadores + parámetros idéntico a compras-pg / create-venta-pg.
 */
import type { PoolClient } from "pg";
import { quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export type TipoMovimiento = "ENTRADA" | "SALIDA" | "AJUSTE";

export type OrigenMovimiento =
  | "compra"
  | "venta"
  | "ajuste_manual"
  | "inventario_inicial"
  | "produccion"
  | "devolucion_venta"
  | "recepcion"
  | "remision"
  | "nota_salida"
  | "ajuste"
  | "transferencia"
  | "anulacion";

export interface FaltanteStockMovimiento {
  producto_id: string;
  producto_nombre: string;
  disponible: number;
  requerido: number;
}

export class StockInsuficienteMovimientoError extends Error {
  faltante: FaltanteStockMovimiento;
  constructor(faltante: FaltanteStockMovimiento) {
    super(`Stock insuficiente para ${faltante.producto_nombre}.`);
    this.name = "StockInsuficienteMovimientoError";
    this.faltante = faltante;
  }
}

export interface RegistrarMovimientoInput {
  empresaId: string;
  productoId: string;
  productoNombre: string;
  productoSku: string;
  tipo: TipoMovimiento;
  /** Cantidad real en unidades base, SIEMPRE positiva. */
  cantidad: number;
  origen: OrigenMovimiento;
  costoUnitario?: number;
  referencia?: string | null;
  documentoTipo?: string | null;
  documentoId?: string | null;
  depositoId?: string | null;
  sucursalId?: string | null;
  observacion?: string | null;
  /** ISO string; default now() del servidor DB. */
  fechaIso?: string | null;
  usuarioId?: string | null;
  usuarioNombre?: string | null;
  /** Para AJUSTE: si true, `cantidad` puede interpretarse con signo negativo. */
  cantidadConSigno?: boolean;
}

export interface RegistrarMovimientoOpts {
  /** Si true, permite que el stock quede negativo (config de empresa). Default false. */
  permitirStockNegativo?: boolean;
  /**
   * Comportamiento cuando el resultado sería negativo y NO se permite negativo:
   *  - 'throw'  → lanza StockInsuficienteMovimientoError (default, flujos nuevos).
   *  - 'floor'  → deja stock en 0 (comportamiento legado de ventas).
   */
  onInsuficiente?: "throw" | "floor";
  /** Si false, sólo inserta el movimiento y no toca productos.stock_actual. Default true. */
  actualizarStock?: boolean;
}

export interface RegistrarMovimientoResult {
  movimientoId: string;
  stockAnterior: number;
  stockNuevo: number;
  cantidadAplicada: number;
}

function deltaDe(tipo: TipoMovimiento, cantidad: number, conSigno: boolean): number {
  if (tipo === "ENTRADA") return Math.abs(cantidad);
  if (tipo === "SALIDA") return -Math.abs(cantidad);
  // AJUSTE
  return conSigno ? cantidad : Math.abs(cantidad);
}

/**
 * Registra un movimiento + actualiza stock atómicamente en la tx del caller.
 * El caller es responsable de BEGIN/COMMIT/ROLLBACK.
 */
export async function registrarMovimientoInventarioTx(
  client: PoolClient,
  schema: string,
  input: RegistrarMovimientoInput,
  opts: RegistrarMovimientoOpts = {},
): Promise<RegistrarMovimientoResult> {
  assertAllowedChatDataSchema(schema);
  const tProd = quoteSchemaTable(schema, "productos");
  const tMov = quoteSchemaTable(schema, "movimientos_inventario");

  const actualizarStock = opts.actualizarStock !== false;
  const onInsuficiente = opts.onInsuficiente ?? "throw";
  const delta = deltaDe(input.tipo, input.cantidad, input.cantidadConSigno === true);

  let stockAnterior = 0;
  let stockNuevo = 0;

  if (actualizarStock) {
    const lock = await client.query(
      `SELECT stock_actual, controla_stock FROM ${tProd} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`,
      [input.productoId, input.empresaId],
    );
    if (lock.rowCount === 0) {
      throw new Error(`Producto ${input.productoId} no encontrado en la empresa.`);
    }
    const controlaStock = lock.rows[0].controla_stock !== false;
    stockAnterior = Number(lock.rows[0].stock_actual ?? 0);
    const bruto = stockAnterior + delta;

    if (controlaStock && bruto < 0 && !opts.permitirStockNegativo) {
      if (onInsuficiente === "throw") {
        throw new StockInsuficienteMovimientoError({
          producto_id: input.productoId,
          producto_nombre: input.productoNombre,
          disponible: stockAnterior,
          requerido: Math.abs(delta),
        });
      }
      stockNuevo = 0; // floor legado
    } else {
      stockNuevo = bruto;
    }

    await client.query(
      `UPDATE ${tProd} SET stock_actual = $1, updated_at = now() WHERE id = $2::uuid AND empresa_id = $3::uuid`,
      [stockNuevo, input.productoId, input.empresaId],
    );
  }

  const ins = await client.query(
    `INSERT INTO ${tMov} (
       empresa_id, producto_id, producto_nombre, producto_sku, tipo, cantidad,
       costo_unitario, origen, referencia, documento_tipo, documento_id,
       deposito_id, sucursal_id, observacion, fecha, created_by, usuario_nombre
     ) VALUES (
       $1::uuid, $2::uuid, $3, $4, $5, $6,
       $7, $8, $9, $10, $11::uuid,
       $12::uuid, $13::uuid, $14, COALESCE($15::timestamptz, now()), $16::uuid, $17
     ) RETURNING id`,
    [
      input.empresaId,
      input.productoId,
      input.productoNombre,
      input.productoSku,
      input.tipo,
      Math.abs(input.cantidad),
      input.costoUnitario ?? 0,
      input.origen,
      input.referencia ?? null,
      input.documentoTipo ?? null,
      input.documentoId ?? null,
      input.depositoId ?? null,
      input.sucursalId ?? null,
      input.observacion ?? null,
      input.fechaIso ?? null,
      input.usuarioId ?? null,
      input.usuarioNombre ?? null,
    ],
  );

  return {
    movimientoId: ins.rows[0].id as string,
    stockAnterior,
    stockNuevo,
    cantidadAplicada: Math.abs(input.cantidad),
  };
}

export interface RevertirDocumentoInput {
  empresaId: string;
  documentoTipo: string;
  documentoId: string;
  usuarioId?: string | null;
  usuarioNombre?: string | null;
  motivo?: string | null;
}

/**
 * Revierte TODOS los movimientos vivos (no anulados) de un documento generando
 * movimientos inversos (origen='anulacion') y marcando los originales como
 * anulados. Nunca borra historial. Atómico dentro de la tx del caller.
 */
export async function revertirMovimientosDeDocumentoTx(
  client: PoolClient,
  schema: string,
  input: RevertirDocumentoInput,
): Promise<{ revertidos: number }> {
  assertAllowedChatDataSchema(schema);
  const tMov = quoteSchemaTable(schema, "movimientos_inventario");

  const origenes = await client.query(
    `SELECT id, producto_id, producto_nombre, producto_sku, tipo, cantidad, costo_unitario,
            deposito_id, sucursal_id, referencia
       FROM ${tMov}
      WHERE empresa_id = $1::uuid AND documento_tipo = $2 AND documento_id = $3::uuid
        AND anulado_at IS NULL AND origen <> 'anulacion'
      FOR UPDATE`,
    [input.empresaId, input.documentoTipo, input.documentoId],
  );

  let revertidos = 0;
  for (const m of origenes.rows) {
    const tipoInverso: TipoMovimiento =
      m.tipo === "ENTRADA" ? "SALIDA" : m.tipo === "SALIDA" ? "ENTRADA" : "AJUSTE";
    const cantidad = Number(m.cantidad);

    // El inverso permite stock negativo (revertir una entrada ya consumida no
    // debe fallar): la reversión es una operación de integridad contable.
    await registrarMovimientoInventarioTx(
      client,
      schema,
      {
        empresaId: input.empresaId,
        productoId: m.producto_id,
        productoNombre: m.producto_nombre,
        productoSku: m.producto_sku,
        tipo: tipoInverso,
        cantidad,
        costoUnitario: Number(m.costo_unitario ?? 0),
        origen: "anulacion",
        referencia: m.referencia ?? null,
        documentoTipo: input.documentoTipo,
        documentoId: input.documentoId,
        depositoId: m.deposito_id ?? null,
        sucursalId: m.sucursal_id ?? null,
        observacion: input.motivo ?? "Reversión por anulación",
        usuarioId: input.usuarioId ?? null,
        usuarioNombre: input.usuarioNombre ?? null,
      },
      { permitirStockNegativo: true, onInsuficiente: "floor" },
    );

    await client.query(
      `UPDATE ${tMov}
          SET anulado_at = now(), anulado_por = $1::uuid, anulado_motivo = $2
        WHERE id = $3::uuid`,
      [input.usuarioId ?? null, input.motivo ?? null, m.id],
    );
    revertidos += 1;
  }

  return { revertidos };
}
