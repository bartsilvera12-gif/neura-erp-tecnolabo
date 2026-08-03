import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { crearGestion, listGestiones } from "@/lib/cobros/server/cobranzas-pg";

export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const clienteId = new URL(request.url).searchParams.get("cliente_id") ?? undefined;
    const gestiones = await listGestiones(schema, ctx.auth.empresa_id, clienteId);
    return NextResponse.json(successResponse({ gestiones }));
  } catch (err) {
    console.error("[/api/cobranzas/gestiones GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las gestiones."), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const clienteId = String(body.cliente_id ?? "");
    if (!clienteId) return NextResponse.json(errorResponse("Falta el cliente."), { status: 400 });
    const out = await crearGestion(schema, ctx.auth.empresa_id, {
      cliente_id: clienteId,
      cuenta_por_cobrar_id: body.cuenta_por_cobrar_id ? String(body.cuenta_por_cobrar_id) : null,
      tipo: String(body.tipo ?? "nota"),
      resultado: body.resultado ? String(body.resultado) : null,
      observacion: body.observacion ? String(body.observacion) : null,
      usuario_id: ctx.auth.usuarioCatalogId ?? null,
      usuario_nombre: ctx.auth.nombre ?? null,
    });
    return NextResponse.json(successResponse(out));
  } catch (err) {
    console.error("[/api/cobranzas/gestiones POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo registrar la gestión."), { status: 500 });
  }
}
