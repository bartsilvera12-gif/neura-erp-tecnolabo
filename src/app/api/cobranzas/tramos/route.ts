import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { getTramos, guardarTramos, type Tramo } from "@/lib/cobros/server/cobranzas-pg";

export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const tramos = await getTramos(schema, ctx.auth.empresa_id);
    return NextResponse.json(successResponse({ tramos }));
  } catch (err) {
    console.error("[/api/cobranzas/tramos GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar los tramos."), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const raw = Array.isArray(body.tramos) ? (body.tramos as Record<string, unknown>[]) : [];
    const tramos: Tramo[] = raw
      .map((t, i) => ({
        nombre: String(t.nombre ?? "").trim(),
        dias_desde: t.dias_desde === null || t.dias_desde === "" ? null : Number(t.dias_desde),
        dias_hasta: t.dias_hasta === null || t.dias_hasta === "" ? null : Number(t.dias_hasta),
        orden: i + 1,
        color: (t.color as string) ?? null,
        activo: t.activo !== false,
      }))
      .filter((t) => t.nombre);
    await guardarTramos(schema, ctx.auth.empresa_id, tramos);
    return NextResponse.json(successResponse({ ok: true, tramos }));
  } catch (err) {
    console.error("[/api/cobranzas/tramos POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron guardar los tramos."), { status: 500 });
  }
}
