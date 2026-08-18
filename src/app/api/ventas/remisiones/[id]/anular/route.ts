import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { anularRemisionVenta } from "@/lib/ventas/server/remisiones-venta-pg";

/** POST /api/ventas/remisiones/[id]/anular — devuelve lo entregado al pendiente. */
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const motivo = typeof body.motivo === "string" && body.motivo.trim() ? body.motivo.trim().slice(0, 500) : null;

    await anularRemisionVenta(schema, ctx.auth.empresa_id, id, motivo, {
      id: ctx.auth.usuarioCatalogId ?? null,
      nombre: ctx.auth.nombre ?? null,
      email: ctx.auth.user?.email ?? null,
    });
    return NextResponse.json(successResponse({ anulada: true }));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo anular la remisión.";
    const status = /no encontrad|no pertenece/i.test(msg) ? 400 : 500;
    console.error("[/api/ventas/remisiones/[id]/anular POST]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
