import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { crearFacturaDesdeVenta, VentaNoFacturableError } from "@/lib/ventas/server/factura-desde-venta-pg";

/**
 * POST /api/ventas/[id]/factura-electronica
 *
 * Crea (o recupera) la factura de una venta para poder emitirla por SIFEN.
 * Idempotente: reintentar devuelve la misma factura y no consume numeración.
 * Desde la factura resultante se sigue el circuito fiscal habitual: generar el
 * borrador del DE, firmar, enviar a la SET y descargar el KuDE.
 */
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);

    const out = await crearFacturaDesdeVenta(schema, ctx.auth.empresa_id, id, {
      id: ctx.auth.usuarioCatalogId ?? null,
      nombre: ctx.auth.nombre ?? null,
      email: ctx.auth.user?.email ?? null,
    });
    return NextResponse.json(successResponse(out));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo generar la factura.";
    const status = err instanceof VentaNoFacturableError ? 400 : 500;
    console.error("[/api/ventas/[id]/factura-electronica POST]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
