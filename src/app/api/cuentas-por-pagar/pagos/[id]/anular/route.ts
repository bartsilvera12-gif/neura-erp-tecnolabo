import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { anularPagoProveedor, PagoProveedorError } from "@/lib/compras/server/pagos-proveedor-pg";

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const motivo = typeof body.motivo === "string" && body.motivo.trim() ? body.motivo.trim() : "Sin motivo especificado";
    await anularPagoProveedor(schema, ctx.auth.empresa_id, id, {
      id: ctx.auth.usuarioCatalogId ?? null,
      nombre: ctx.auth.nombre ?? null,
      email: ctx.auth.user?.email ?? null,
    }, motivo);
    return NextResponse.json(successResponse({ ok: true }));
  } catch (err) {
    if (err instanceof PagoProveedorError) return NextResponse.json(errorResponse(err.message), { status: err.status });
    console.error("[/api/cuentas-por-pagar/pagos/[id]/anular]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo anular el pago."), { status: 500 });
  }
}
