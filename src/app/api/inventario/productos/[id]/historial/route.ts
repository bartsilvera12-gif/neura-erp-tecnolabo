import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { getHistorialProducto } from "@/lib/inventario/server/historial-producto-pg";

/** GET /api/inventario/productos/[id]/historial — movimientos, compras, evolución de costos. */
export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const hist = await getHistorialProducto(schema, ctx.auth.empresa_id, id);
    if (!hist) return NextResponse.json(errorResponse("Producto no encontrado."), { status: 404 });
    return NextResponse.json(successResponse(hist));
  } catch (err) {
    console.error("[/api/inventario/productos/[id]/historial GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo cargar el historial del producto."), { status: 500 });
  }
}
