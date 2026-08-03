/**
 * Historial por producto (Fase 3): movimientos, compras por proveedor,
 * evolución de costos y comparación costo/precio/margen.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface HistorialProducto {
  producto: {
    id: string;
    nombre: string;
    sku: string | null;
    stock_actual: number;
    costo_promedio: number;
    precio_venta: number;
    precio_mayorista: number | null;
    margen_pct: number | null;
  };
  movimientos: Array<{
    id: string;
    tipo: string;
    cantidad: number;
    origen: string;
    referencia: string | null;
    fecha: string;
    usuario_nombre: string | null;
    observacion: string | null;
  }>;
  compras: Array<{
    fecha: string;
    proveedor_nombre: string | null;
    cantidad: number;
    costo_unitario: number;
    moneda: string;
    numero_control: string;
  }>;
  evolucion_costos: Array<{ fecha: string; costo_unitario: number }>;
}

export async function getHistorialProducto(
  schema: string,
  empresaId: string,
  productoId: string,
): Promise<HistorialProducto | null> {
  assertAllowedChatDataSchema(schema);
  const pool = getChatPostgresPool();
  if (!pool) throw new Error("Pool no disponible.");
  const tP = quoteSchemaTable(schema, "productos");
  const tM = quoteSchemaTable(schema, "movimientos_inventario");
  const tC = quoteSchemaTable(schema, "compras");
  const client = await pool.connect();
  try {
    const prod = await client.query(
      `SELECT id, nombre, sku, COALESCE(stock_actual,0)::numeric AS stock_actual,
              COALESCE(costo_promedio,0)::numeric AS costo_promedio,
              COALESCE(precio_venta,0)::numeric AS precio_venta,
              precio_mayorista
         FROM ${tP} WHERE id = $1::uuid AND empresa_id = $2::uuid`,
      [productoId, empresaId],
    );
    if (prod.rowCount === 0) return null;
    const p = prod.rows[0];
    const costo = Number(p.costo_promedio) || 0;
    const precio = Number(p.precio_venta) || 0;
    const margen_pct = precio > 0 ? Math.round(((precio - costo) / precio) * 1000) / 10 : null;

    const movs = await client.query(
      `SELECT id, tipo, cantidad, origen, referencia, fecha, usuario_nombre, observacion
         FROM ${tM}
        WHERE producto_id = $1::uuid AND empresa_id = $2::uuid AND anulado_at IS NULL
        ORDER BY fecha DESC LIMIT 200`,
      [productoId, empresaId],
    );

    const compras = await client.query(
      `SELECT fecha, proveedor_nombre, cantidad, costo_unitario, moneda, numero_control
         FROM ${tC}
        WHERE producto_id = $1::uuid AND empresa_id = $2::uuid AND anulada_at IS NULL
        ORDER BY fecha DESC LIMIT 100`,
      [productoId, empresaId],
    );

    const evol = [...compras.rows]
      .reverse()
      .map((r) => ({ fecha: String(r.fecha), costo_unitario: Number(r.costo_unitario) || 0 }));

    return {
      producto: {
        id: p.id,
        nombre: p.nombre,
        sku: p.sku,
        stock_actual: Number(p.stock_actual),
        costo_promedio: costo,
        precio_venta: precio,
        precio_mayorista: p.precio_mayorista != null ? Number(p.precio_mayorista) : null,
        margen_pct,
      },
      movimientos: movs.rows.map((r) => ({
        id: r.id,
        tipo: r.tipo,
        cantidad: Number(r.cantidad),
        origen: r.origen,
        referencia: r.referencia,
        fecha: String(r.fecha),
        usuario_nombre: r.usuario_nombre,
        observacion: r.observacion,
      })),
      compras: compras.rows.map((r) => ({
        fecha: String(r.fecha),
        proveedor_nombre: r.proveedor_nombre,
        cantidad: Number(r.cantidad),
        costo_unitario: Number(r.costo_unitario) || 0,
        moneda: r.moneda,
        numero_control: r.numero_control,
      })),
      evolucion_costos: evol,
    };
  } finally {
    client.release();
  }
}
