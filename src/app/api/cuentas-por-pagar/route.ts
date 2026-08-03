import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { listCuentasPorPagar } from "@/lib/compras/server/cuentas-por-pagar-pg";

/** GET /api/cuentas-por-pagar — listado de obligaciones a proveedores. */
export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const { searchParams } = new URL(request.url);
    const estado = searchParams.get("estado") ?? undefined;
    const proveedorId = searchParams.get("proveedor_id") ?? undefined;
    const cuentas = await listCuentasPorPagar(schema, ctx.auth.empresa_id, { estado, proveedorId });
    return NextResponse.json(successResponse({ cuentas }));
  } catch (err) {
    console.error("[/api/cuentas-por-pagar GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las cuentas por pagar."), { status: 500 });
  }
}
