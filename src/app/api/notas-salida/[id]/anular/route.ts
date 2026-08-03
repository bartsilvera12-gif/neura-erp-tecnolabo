import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { anularNotaSalida } from "@/lib/inventario/server/notas-salida-pg";

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const motivo = typeof body.motivo === "string" && body.motivo.trim() ? body.motivo.trim() : "Sin motivo especificado";
    await anularNotaSalida(schema, ctx.auth.empresa_id, id, {
      id: ctx.auth.usuarioCatalogId ?? null,
      nombre: ctx.auth.nombre ?? null,
      email: ctx.auth.user?.email ?? null,
    }, motivo);
    return NextResponse.json(successResponse({ ok: true }));
  } catch (err) {
    const msg = err instanceof Error ? err.message : "No se pudo anular.";
    const status = /no encontrad|solo se anula/i.test(msg) ? 400 : 500;
    console.error("[/api/notas-salida/[id]/anular]", msg);
    return NextResponse.json(errorResponse(msg), { status });
  }
}
