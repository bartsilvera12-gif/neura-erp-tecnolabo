import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuth } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { crearPromesa, listPromesas } from "@/lib/cobros/server/cobranzas-pg";

export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const clienteId = new URL(request.url).searchParams.get("cliente_id") ?? undefined;
    const promesas = await listPromesas(schema, ctx.auth.empresa_id, clienteId);
    return NextResponse.json(successResponse({ promesas }));
  } catch (err) {
    console.error("[/api/cobranzas/promesas GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar las promesas."), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuth(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const clienteId = String(body.cliente_id ?? "");
    const fecha = String(body.fecha_promesa ?? "");
    if (!clienteId || !fecha) return NextResponse.json(errorResponse("Faltan cliente y fecha de promesa."), { status: 400 });
    const out = await crearPromesa(schema, ctx.auth.empresa_id, {
      cliente_id: clienteId,
      cuenta_por_cobrar_id: body.cuenta_por_cobrar_id ? String(body.cuenta_por_cobrar_id) : null,
      fecha_promesa: fecha,
      monto: Number(body.monto) || 0,
      observacion: body.observacion ? String(body.observacion) : null,
      responsable_id: ctx.auth.usuarioCatalogId ?? null,
      responsable_nombre: ctx.auth.nombre ?? null,
      recordatorio_at: body.recordatorio_at ? String(body.recordatorio_at) : null,
      created_by: ctx.auth.usuarioCatalogId ?? null,
    });
    return NextResponse.json(successResponse(out));
  } catch (err) {
    console.error("[/api/cobranzas/promesas POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo registrar la promesa."), { status: 500 });
  }
}
