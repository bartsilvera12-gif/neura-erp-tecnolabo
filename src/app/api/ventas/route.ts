import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import type { Venta, LineaVenta, TipoIvaVenta, TipoPrecioVenta } from "@/lib/ventas/types";

interface VentaRow {
  id: string;
  empresa_id: string;
  numero_control: string;
  moneda: string;
  tipo_cambio: number | string;
  subtotal: number | string;
  monto_iva: number | string;
  total: number | string;
  tipo_venta: string;
  plazo_dias: number | null;
  fecha: string;
  usuario_nombre?: string | null;
}

interface VentaItemRow {
  venta_id: string;
  producto_id: string;
  producto_nombre: string;
  sku: string;
  cantidad: number | string;
  precio_venta_original: number | string;
  precio_venta: number | string;
  tipo_iva: string;
  tipo_precio?: string;
  subtotal: number | string;
  monto_iva: number | string;
  total_linea: number | string;
}

function num(v: number | string): number {
  return typeof v === "number" ? v : Number(v);
}

/**
 * Número legal a partir del CDC: posiciones 12-14 establecimiento,
 * 15-17 punto de expedición, 18-24 número. Devuelve null si el CDC no está
 * completo (venta sin DE aprobado todavía).
 */
function numeroLegalDesdeCdc(cdc: string | null | undefined): string | null {
  const s = String(cdc ?? "").trim();
  if (s.length < 24) return null;
  return s.slice(11, 14) + "-" + s.slice(14, 17) + "-" + s.slice(17, 24);
}

function mapItems(rows: VentaItemRow[]): LineaVenta[] {
  return rows.map((r) => ({
    producto_id: r.producto_id,
    producto_nombre: r.producto_nombre,
    sku: r.sku,
    cantidad: num(r.cantidad),
    precio_venta_original: num(r.precio_venta_original),
    precio_venta: num(r.precio_venta),
    tipo_iva: r.tipo_iva as TipoIvaVenta,
    tipo_precio: (r.tipo_precio === "mayorista" || r.tipo_precio === "distribuidor" || r.tipo_precio === "costo" ? r.tipo_precio : "minorista") as TipoPrecioVenta,
    subtotal: num(r.subtotal),
    monto_iva: num(r.monto_iva),
    total_linea: num(r.total_linea),
  }));
}

/** GET /api/ventas — listado vía PostgREST (compatible Hostinger sin pool). */
export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const empresaId = ctx.auth.empresa_id;

    const ventasQ = await ctx.supabase
      .from("ventas")
      .select(
        "id, empresa_id, numero_control, moneda, tipo_cambio, subtotal, monto_iva, total, tipo_venta, plazo_dias, metodo_pago, fecha, genera_nota_remision, nota_remision_numero, usuario_nombre, estado, anulada_at, anulada_motivo"
      )
      .eq("empresa_id", empresaId)
      .order("fecha", { ascending: false })
      .limit(500);
    if (ventasQ.error) throw new Error(ventasQ.error.message);

    const itemsQ = await ctx.supabase
      .from("ventas_items")
      .select(
        "venta_id, producto_id, producto_nombre, sku, cantidad, precio_venta_original, precio_venta, tipo_iva, tipo_precio, subtotal, monto_iva, total_linea"
      )
      .eq("empresa_id", empresaId);
    if (itemsQ.error) throw new Error(itemsQ.error.message);

    /*
      Numeración fiscal: la pantalla debe mostrar el número de la factura
      electrónica, no el correlativo interno de caja. Se resuelve acá y no en
      el cliente para que la lista, la búsqueda y el detalle usen el mismo dato.
    */
    const facturasQ = await ctx.supabase
      .from("facturas")
      .select("id, venta_id, numero_factura")
      .eq("empresa_id", empresaId)
      .not("venta_id", "is", null);
    if (facturasQ.error) throw new Error(facturasQ.error.message);

    // El CDC es un lujo: si la tabla no responde se cae al número FAC-xxxxxx,
    // que igual es el correlativo fiscal. No vale romper el listado por esto.
    const deQ = await ctx.supabase
      .from("factura_electronica")
      .select("factura_id, cdc")
      .eq("empresa_id", empresaId);
    if (deQ.error) console.warn("[/api/ventas GET] sin CDC:", deQ.error.message);

    const cdcPorFactura = new Map<string, string>();
    for (const d of (deQ.data ?? []) as { factura_id: string; cdc: string | null }[]) {
      if (d.cdc) cdcPorFactura.set(String(d.factura_id), String(d.cdc));
    }
    const fiscalPorVenta = new Map<string, { numero_factura: string | null; numero_legal: string | null }>();
    for (const f of (facturasQ.data ?? []) as { id: string; venta_id: string | null; numero_factura: string | null }[]) {
      if (!f.venta_id) continue;
      fiscalPorVenta.set(String(f.venta_id), {
        numero_factura: f.numero_factura ?? null,
        numero_legal: numeroLegalDesdeCdc(cdcPorFactura.get(String(f.id))),
      });
    }

    const ventasRows = (ventasQ.data ?? []) as VentaRow[];
    const itemsRows = (itemsQ.data ?? []) as VentaItemRow[];

    const byVenta = new Map<string, VentaItemRow[]>();
    for (const row of itemsRows) {
      const list = byVenta.get(row.venta_id) ?? [];
      list.push(row);
      byVenta.set(row.venta_id, list);
    }

    const ventas: Venta[] = ventasRows.map((r) => {
      const lineRows = byVenta.get(r.id) ?? [];
      return {
        id: r.id,
        numero_control: r.numero_control,
        items: mapItems(lineRows),
        moneda: r.moneda === "USD" ? "USD" : "GS",
        tipo_cambio: num(r.tipo_cambio),
        subtotal: num(r.subtotal),
        monto_iva: num(r.monto_iva),
        total: num(r.total),
        tipo_venta: r.tipo_venta === "CREDITO" ? "CREDITO" : "CONTADO",
        plazo_dias: r.plazo_dias ?? undefined,
        metodo_pago: (r as unknown as { metodo_pago?: string }).metodo_pago === "tarjeta"
          ? "tarjeta"
          : (r as unknown as { metodo_pago?: string }).metodo_pago === "transferencia"
          ? "transferencia"
          : (r as unknown as { metodo_pago?: string }).metodo_pago === "efectivo"
          ? "efectivo"
          : (r as unknown as { metodo_pago?: string }).metodo_pago === "mixto"
          ? "mixto"
          : undefined,
        genera_nota_remision: (r as unknown as { genera_nota_remision?: boolean }).genera_nota_remision === true,
        nota_remision_numero: (r as unknown as { nota_remision_numero?: string | null }).nota_remision_numero ?? null,
        numero_factura: fiscalPorVenta.get(r.id)?.numero_factura ?? null,
        numero_legal: fiscalPorVenta.get(r.id)?.numero_legal ?? null,
        fecha: r.fecha,
        usuario_nombre: r.usuario_nombre ?? null,
        estado: ((): "activa" | "anulada" | "parcialmente_devuelta" | "devuelta_total" => {
          const e = (r as unknown as { estado?: string }).estado;
          if (e === "anulada") return "anulada";
          if (e === "devuelta_total") return "devuelta_total";
          if (e === "parcialmente_devuelta") return "parcialmente_devuelta";
          return "activa";
        })(),
        anulada_at: (r as unknown as { anulada_at?: string | null }).anulada_at ?? null,
        anulada_motivo: (r as unknown as { anulada_motivo?: string | null }).anulada_motivo ?? null,
      };
    });

    return NextResponse.json(successResponse({ ventas }));
  } catch (err) {
    console.error("[/api/ventas GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las ventas."), { status: 500 });
  }
}
