import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { getRemisionParaEdicion } from "@/lib/ventas/server/remisiones-pg";
import { renderRemisionVentaHTML } from "@/lib/ventas/remision-venta-html";
import { logoClienteSrc } from "@/lib/documentos/logo-embed";

/**
 * GET /api/remisiones/[id]/pdf?auto=1
 *
 * Nota de remisión de una FACTURA (rama crédito/CxC).
 *
 * Usa el MISMO documento que la remisión de venta: una sola nota de remisión
 * para todo el ERP, con el logo y los colores de la marca. Antes esta ruta tenía
 * su propio HTML sin membrete, así que según de dónde naciera la remisión salía
 * un documento distinto.
 */
export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);

    const data = await getRemisionParaEdicion(schema, ctx.auth.empresa_id, id);
    if (!data) return new NextResponse("Remisión no encontrada", { status: 404 });

    const r = data.remision;
    const html = renderRemisionVentaHTML(
      {
        remision: {
          numero: r.numero,
          estado: r.estado,
          fecha: String(r.fecha),
          // Esta rama no nace de una venta: la fila "Venta" no se imprime.
          numero_control: null,
          numero_orden_compra: r.numero_orden_compra ?? null,
          factura_numero: r.numero_factura ?? null,
          factura_cdc: null,
          factura_estado_sifen: null,
          cliente_nombre: r.cliente_nombre ?? null,
          observacion: r.observacion ?? null,
          usuario_creador_nombre: r.usuario_confirmador_nombre ?? r.usuario_creador_nombre ?? null,
          anulada_motivo: null,
        },
        lineas: data.lineas.map((l) => ({
          producto_nombre: l.producto_nombre,
          sku: l.sku,
          cantidad_vendida: l.cantidad_facturada,
          en_esta_remision: l.en_esta_remision,
          pendiente: Math.max(0, l.cantidad_facturada - l.cantidad_entregada),
          observacion: l.observacion,
        })),
      },
      logoClienteSrc(),
    );

    return new NextResponse(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  } catch (err) {
    console.error("[/api/remisiones/[id]/pdf]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo generar el documento."), { status: 500 });
  }
}
