import type { AppSupabaseClient } from "@/lib/supabase/schema";

export type FacturaDeVenta = {
  numero_factura: string | null;
  /** Estado de la factura en BD: Pendiente | Pagado | Vencido | Anulado | Corregida NC. */
  estado: string | null;
};

/**
 * Mapa venta_id → { numero_factura (FAC-xxxxxx), estado } para un conjunto de
 * ventas de la empresa. Permite mostrar en el estado de cuenta el número de
 * factura en lugar del correlativo interno VTA-, y detectar las facturas
 * corregidas por Nota de Crédito ("Corregida NC") o anuladas, para marcarlas y
 * no sumarlas al saldo. Solo lectura.
 *
 * Una venta a crédito puede no tener factura emitida todavía: en ese caso no
 * aparece en el mapa. La relación es 1:1 (índice único parcial
 * `facturas_venta_id_uniq` sobre venta_id).
 */
export async function facturaPorVenta(
  supabase: AppSupabaseClient,
  empresaId: string,
  ventaIds: readonly (string | null | undefined)[]
): Promise<Map<string, FacturaDeVenta>> {
  const ids = [...new Set(ventaIds.filter((v): v is string => !!v))];
  const map = new Map<string, FacturaDeVenta>();
  if (ids.length === 0) return map;

  const fq = await supabase
    .from("facturas")
    .select("venta_id, numero_factura, estado")
    .eq("empresa_id", empresaId)
    .in("venta_id", ids);
  if (fq.error) throw new Error(fq.error.message);

  for (const f of (fq.data ?? []) as Record<string, unknown>[]) {
    const vid = f.venta_id ? String(f.venta_id) : "";
    if (!vid) continue;
    map.set(vid, {
      numero_factura: f.numero_factura ? String(f.numero_factura) : null,
      estado: f.estado ? String(f.estado) : null,
    });
  }
  return map;
}

/**
 * true si la factura quedó sin efecto de cobro: corregida en su totalidad por
 * una Nota de Crédito ("Corregida NC") o anulada. Se usa para marcarla en el
 * estado de cuenta y excluirla del saldo/vencido.
 */
export function facturaSinEfectoCobro(estadoFactura: string | null | undefined): boolean {
  const e = String(estadoFactura ?? "").trim();
  return e === "Corregida NC" || e === "Anulado";
}
