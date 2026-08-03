import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuthWithRol } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { asignarRolUsuario, quitarRolUsuario } from "@/lib/auth/roles-pg";

function esAdmin(rol?: string): boolean {
  const r = (rol ?? "").toLowerCase();
  return r === "super_admin" || r === "admin" || r === "administrador";
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    if (!esAdmin(ctx.auth.rol)) return NextResponse.json(errorResponse("Solo un administrador puede asignar roles."), { status: 403 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const email = String(body.usuario_email ?? "").trim();
    const rolId = String(body.rol_id ?? "").trim();
    if (!email || !rolId) return NextResponse.json(errorResponse("Faltan usuario y rol."), { status: 400 });
    if (body.quitar === true) {
      await quitarRolUsuario(schema, ctx.auth.empresa_id, email, rolId);
    } else {
      await asignarRolUsuario(schema, ctx.auth.empresa_id, email, rolId, body.usuario_id ? String(body.usuario_id) : null);
    }
    return NextResponse.json(successResponse({ ok: true }));
  } catch (err) {
    console.error("[/api/usuario-roles POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo actualizar la asignación."), { status: 500 });
  }
}
