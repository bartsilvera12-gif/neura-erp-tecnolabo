import { NextRequest, NextResponse } from "next/server";
import { getTenantSupabaseFromAuthWithRol } from "@/lib/supabase/tenant-api";
import { fetchDataSchemaForEmpresaId } from "@/lib/supabase/empresa-data-schema";
import { successResponse, errorResponse } from "@/lib/api/response";
import { API_ERRORS } from "@/lib/api/errors";
import { listRoles, guardarRol, eliminarRol, listUsuarioRoles } from "@/lib/auth/roles-pg";
import { PERMISOS, PERMISO_LABEL, type Permiso } from "@/lib/auth/permisos";

function esAdmin(rol?: string): boolean {
  const r = (rol ?? "").toLowerCase();
  return r === "super_admin" || r === "admin" || r === "administrador";
}

export async function GET(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const [roles, asignaciones] = await Promise.all([
      listRoles(schema, ctx.auth.empresa_id),
      listUsuarioRoles(schema, ctx.auth.empresa_id),
    ]);
    const catalogo = PERMISOS.map((p) => ({ permiso: p, label: PERMISO_LABEL[p as Permiso] }));
    return NextResponse.json(successResponse({ roles, asignaciones, catalogo }));
  } catch (err) {
    console.error("[/api/roles GET]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudieron cargar los roles."), { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    if (!esAdmin(ctx.auth.rol)) return NextResponse.json(errorResponse("Solo un administrador puede gestionar roles."), { status: 403 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const nombre = String(body.nombre ?? "").trim();
    if (!nombre) return NextResponse.json(errorResponse("El nombre del rol es obligatorio."), { status: 400 });
    const codigo = String(body.codigo ?? nombre.toLowerCase().replace(/\s+/g, "_")).trim();
    const permisosValidos = (Array.isArray(body.permisos) ? body.permisos : []).map(String).filter((p) => (PERMISOS as readonly string[]).includes(p));
    const out = await guardarRol(schema, ctx.auth.empresa_id, {
      id: body.id ? String(body.id) : undefined,
      nombre,
      codigo,
      descripcion: body.descripcion ? String(body.descripcion) : null,
      activo: body.activo !== false,
      permisos: permisosValidos,
    });
    return NextResponse.json(successResponse(out));
  } catch (err) {
    console.error("[/api/roles POST]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo guardar el rol."), { status: 500 });
  }
}

export async function DELETE(request: NextRequest) {
  try {
    const ctx = await getTenantSupabaseFromAuthWithRol(request);
    if (!ctx) return NextResponse.json(errorResponse(API_ERRORS.UNAUTHORIZED), { status: 401 });
    if (!esAdmin(ctx.auth.rol)) return NextResponse.json(errorResponse("Solo un administrador puede eliminar roles."), { status: 403 });
    const schema = await fetchDataSchemaForEmpresaId(ctx.auth.empresa_id);
    const id = new URL(request.url).searchParams.get("id") ?? "";
    if (!id) return NextResponse.json(errorResponse("Falta el id."), { status: 400 });
    await eliminarRol(schema, ctx.auth.empresa_id, id);
    return NextResponse.json(successResponse({ ok: true }));
  } catch (err) {
    console.error("[/api/roles DELETE]", err instanceof Error ? err.message : err);
    return NextResponse.json(errorResponse("No se pudo eliminar el rol."), { status: 500 });
  }
}
