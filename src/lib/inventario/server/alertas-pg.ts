/**
 * Alertas de stock mínimo (Fase 3).
 * Productos con control de stock cuyo stock_actual está en o por debajo del mínimo.
 * Usa el pool PG porque PostgREST no compara dos columnas entre sí.
 */
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";

export interface AlertaStock {
  id: string;
  nombre: string;
  sku: string | null;
  codigo_barras: string | null;
  stock_actual: number;
  stock_minimo: number;
  faltante: number;
  costo_promedio: number;
  precio_venta: number;
}

export async function getAlertasStockMinimo(schema: string, empresaId: string): Promise<AlertaStock[]> {
  assertAllowedChatDataSchema(schema);
  const pool = getChatPostgresPool();
  if (!pool) throw new Error("Pool no disponible.");
  const tP = quoteSchemaTable(schema, "productos");
  const client = await pool.connect();
  try {
    const res = await client.query(
      `SELECT id, nombre, sku, codigo_barras,
              COALESCE(stock_actual,0)::numeric AS stock_actual,
              COALESCE(stock_minimo,0)::numeric AS stock_minimo,
              GREATEST(0, COALESCE(stock_minimo,0) - COALESCE(stock_actual,0))::numeric AS faltante,
              COALESCE(costo_promedio,0)::numeric AS costo_promedio,
              COALESCE(precio_venta,0)::numeric AS precio_venta
         FROM ${tP}
        WHERE empresa_id = $1::uuid
          AND controla_stock IS NOT FALSE
          AND stock_minimo IS NOT NULL AND stock_minimo > 0
          AND COALESCE(stock_actual,0) <= stock_minimo
        ORDER BY (COALESCE(stock_minimo,0) - COALESCE(stock_actual,0)) DESC`,
      [empresaId],
    );
    return res.rows.map((r) => ({
      id: r.id,
      nombre: r.nombre,
      sku: r.sku,
      codigo_barras: r.codigo_barras,
      stock_actual: Number(r.stock_actual),
      stock_minimo: Number(r.stock_minimo),
      faltante: Number(r.faltante),
      costo_promedio: Number(r.costo_promedio),
      precio_venta: Number(r.precio_venta),
    }));
  } finally {
    client.release();
  }
}
