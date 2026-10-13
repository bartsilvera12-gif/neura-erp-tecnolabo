import type { AppSupabaseClient } from "@/lib/supabase/schema";

/**
 * Mapa venta_id → numero_factura (FAC-xxxxxx) para un conjunto de ventas de la
 * empresa. Permite mostrar en el estado de cuenta el número de factura en lugar
 * del correlativo interno de venta (VTA-). Solo lectura.
 *
 * Una venta a crédito puede no tener factura emitida todavía: en ese caso no
 * aparece en el mapa (el llamador cae al número de venta). La relación es 1:1
 * (índice único parcial `facturas_venta_id_uniq` sobre venta_id).
 */
export async function numeroFacturaPorVenta(
  supabase: AppSupabaseClient,
  empresaId: string,
  ventaIds: readonly (string | null | undefined)[]
): Promise<Map<string, string>> {
  const ids = [...new Set(ventaIds.filter((v): v is string => !!v))];
  const map = new Map<string, string>();
  if (ids.length === 0) return map;

  const fq = await supabase
    .from("facturas")
    .select("venta_id, numero_factura")
    .eq("empresa_id", empresaId)
    .in("venta_id", ids);
  if (fq.error) throw new Error(fq.error.message);

  for (const f of (fq.data ?? []) as Record<string, unknown>[]) {
    const vid = f.venta_id ? String(f.venta_id) : "";
    const num = f.numero_factura ? String(f.numero_factura) : "";
    if (vid && num) map.set(vid, num);
  }
  return map;
}
