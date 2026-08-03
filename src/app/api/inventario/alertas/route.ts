import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { getAlertasStockMinimo } from "@/lib/inventario/server/alertas-pg";

/** GET /api/inventario/alertas — productos en o bajo el stock mínimo. */
export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const alertas = await getAlertasStockMinimo(schema, ctx.auth.empresa_id);
    return NextResponse.json(successResponse({ alertas, total: alertas.length }));
  } catch (err) {
    console.error("[/api/inventario/alertas GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las alertas de stock."), { status: 500 });
  }
}
