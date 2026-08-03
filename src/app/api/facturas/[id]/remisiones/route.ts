import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import {
  crearRemision,
  getResumenFacturaEntrega,
  listRemisionesDeFactura,
  RemisionExcedenteError,
  StockInsuficienteMovimientoError,
  type RemisionItemInput,
} from "@/lib/ventas/server/remisiones-pg";

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const [resumen, remisiones] = await Promise.all([
      getResumenFacturaEntrega(schema, ctx.auth.empresa_id, id),
      listRemisionesDeFactura(schema, ctx.auth.empresa_id, id),
    ]);
    if (!resumen) return NextResponse.json(errorResponse("Factura no encontrada."), { status: 404 });
    return NextResponse.json(successResponse({ resumen, remisiones }));
  } catch (err) {
    console.error("[/api/facturas/[id]/remisiones GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las remisiones."), { status: 500 });
  }
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const rawItems = Array.isArray(body.items) ? (body.items as Record<string, unknown>[]) : [];
    const items: RemisionItemInput[] = rawItems
      .map((it) => ({
        factura_item_id: String(it.factura_item_id ?? ""),
        producto_id: String(it.producto_id ?? ""),
        producto_nombre: String(it.producto_nombre ?? ""),
        sku: (it.sku as string) ?? null,
        cantidad: Number(it.cantidad) || 0,
        costo_unitario: Number(it.costo_unitario) || 0,
      }))
      .filter((it) => it.producto_id && it.cantidad > 0);
    if (items.length === 0) return NextResponse.json(errorResponse("Indicá al menos un producto con cantidad a remitir."), { status: 400 });

    const out = await crearRemision(
      schema,
      ctx.auth.empresa_id,
      {
        factura_id: id,
        deposito_id: (body.deposito_id as string) ?? null,
        sucursal_id: (body.sucursal_id as string) ?? null,
        observacion: (body.observacion as string) ?? null,
        firma_entrega: (body.firma_entrega as string) ?? null,
        firma_recepcion: (body.firma_recepcion as string) ?? null,
        items,
        confirmar: body.confirmar === true,
      },
      { id: ctx.auth.usuarioCatalogId ?? null, nombre: ctx.auth.nombre ?? null, email: ctx.auth.user?.email ?? null },
    );
    return NextResponse.json(successResponse(out));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo crear la remisión.";
    const status =
      err instanceof RemisionExcedenteError || err instanceof StockInsuficienteMovimientoError ? 409 : /no encontrad|no tiene/i.test(msg) ? 400 : 500;
    console.error("[/api/facturas/[id]/remisiones POST]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
