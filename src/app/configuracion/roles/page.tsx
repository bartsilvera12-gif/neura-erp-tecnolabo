"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, Plus, Trash2, Save, ShieldCheck } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Rol = { id: string; nombre: string; codigo: string; descripcion: string | null; activo: boolean; permisos: string[] };
type Asignacion = { usuario_email: string; rol_id: string };
type PermCat = { permiso: string; label: string };
type UsuarioLite = { email: string; nombre: string };

const inputClass = "w-full rounded-md border border-gray-300 px-3 py-2 text-sm";

export default function RolesPage() {
  const [roles, setRoles] = useState<Rol[]>([]);
  const [catalogo, setCatalogo] = useState<PermCat[]>([]);
  const [asignaciones, setAsignaciones] = useState<Asignacion[]>([]);
  const [usuarios, setUsuarios] = useState<UsuarioLite[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [nuevoNombre, setNuevoNombre] = useState("");

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const [rr, ru] = await Promise.all([
        fetchWithSupabaseSession("/api/roles", { cache: "no-store" }),
        fetchWithSupabaseSession("/api/usuarios", { cache: "no-store" }),
      ]);
      const br = await rr.json();
      const bu = await ru.json();
      if (!rr.ok || br?.success === false) { setError(br?.error ?? "No se pudieron cargar los roles."); return; }
      setRoles((br.data.roles ?? []) as Rol[]);
      setCatalogo((br.data.catalogo ?? []) as PermCat[]);
      setAsignaciones((br.data.asignaciones ?? []) as Asignacion[]);
      const list = (bu?.data?.usuarios ?? bu?.data ?? []) as Record<string, unknown>[];
      setUsuarios(list.map((u) => ({ email: String(u.email ?? ""), nombre: String(u.nombre ?? u.email ?? "") })).filter((u) => u.email));
    } catch { setError("Error de red."); } finally { setLoading(false); }
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  function togglePerm(rolIdx: number, permiso: string) {
    setRoles((prev) => prev.map((r, i) => {
      if (i !== rolIdx) return r;
      const has = r.permisos.includes(permiso);
      return { ...r, permisos: has ? r.permisos.filter((p) => p !== permiso) : [...r.permisos, permiso] };
    }));
  }

  async function guardarRol(rol: Rol) {
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession("/api/roles", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: rol.id, nombre: rol.nombre, codigo: rol.codigo, descripcion: rol.descripcion, activo: rol.activo, permisos: rol.permisos }) });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo guardar."); return; }
      setOk(`Rol "${rol.nombre}" guardado.`);
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  async function crearRol() {
    if (!nuevoNombre.trim()) return;
    setBusy(true); setError(null);
    try {
      const res = await fetchWithSupabaseSession("/api/roles", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ nombre: nuevoNombre.trim(), permisos: [] }) });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo crear."); return; }
      setNuevoNombre("");
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  async function eliminarRol(id: string) {
    if (!confirm("¿Eliminar este rol? Se quitará de los usuarios asignados.")) return;
    await fetchWithSupabaseSession(`/api/roles?id=${id}`, { method: "DELETE" });
    await cargar();
  }

  async function toggleAsignacion(email: string, rolId: string, tiene: boolean) {
    await fetchWithSupabaseSession("/api/usuario-roles", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ usuario_email: email, rol_id: rolId, quitar: tiene }) });
    await cargar();
  }

  if (loading) return <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>;

  return (
    <div className="space-y-6 max-w-5xl">
      <Link href="/configuracion" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a configuración
      </Link>
      <div className="flex items-center gap-3">
        <ShieldCheck className="h-7 w-7 text-[#4FAEB2]" />
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Roles y permisos</h1>
          <p className="text-sm text-gray-500">Permisos por acción. Un usuario sin roles conserva el acceso legado; al asignarle un rol se aplican sus permisos (en frontend y backend).</p>
        </div>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      <div className="flex items-end gap-2">
        <div className="flex-1 max-w-xs">
          <label className="block text-xs font-medium text-gray-600 mb-1">Nuevo rol</label>
          <input value={nuevoNombre} onChange={(e) => setNuevoNombre(e.target.value)} className={inputClass} placeholder="Ej: Cajero, Depósito, Cobrador" />
        </div>
        <button onClick={crearRol} disabled={busy || !nuevoNombre.trim()} className="inline-flex items-center gap-1 rounded-md bg-[#4FAEB2] px-3 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50"><Plus className="h-4 w-4" /> Crear</button>
      </div>

      {roles.map((rol, i) => (
        <div key={rol.id} className="bg-white rounded-xl border border-slate-200 shadow-sm p-5 space-y-3">
          <div className="flex items-center justify-between">
            <input value={rol.nombre} onChange={(e) => setRoles((prev) => prev.map((r, idx) => idx === i ? { ...r, nombre: e.target.value } : r))} className="text-lg font-semibold text-gray-800 border-b border-transparent focus:border-slate-300 outline-none" />
            <button onClick={() => eliminarRol(rol.id)} className="text-red-600 hover:text-red-700"><Trash2 className="h-4 w-4" /></button>
          </div>
          <div className="flex flex-wrap gap-2">
            {catalogo.map((c) => {
              const has = rol.permisos.includes(c.permiso);
              return (
                <label key={c.permiso} className={`inline-flex items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-xs font-medium cursor-pointer ${has ? "border-[#4FAEB2] bg-[#4FAEB2]/8 text-[#3F8E91]" : "border-slate-200 text-slate-600"}`}>
                  <input type="checkbox" checked={has} onChange={() => togglePerm(i, c.permiso)} className="accent-[#4FAEB2]" />
                  {c.label}
                </label>
              );
            })}
          </div>
          <div className="flex justify-end">
            <button onClick={() => guardarRol(rol)} disabled={busy} className="inline-flex items-center gap-1.5 rounded-md bg-[#4FAEB2] px-4 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50"><Save className="h-4 w-4" /> Guardar</button>
          </div>
        </div>
      ))}

      {/* Asignación de roles a usuarios */}
      {usuarios.length > 0 && roles.length > 0 && (
        <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
          <h2 className="text-sm font-semibold text-gray-700 mb-3">Asignación de roles</h2>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="text-left text-xs text-gray-500 uppercase">
                <tr><th className="py-2 pr-2">Usuario</th>{roles.map((r) => <th key={r.id} className="py-2 px-2 text-center">{r.nombre}</th>)}</tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {usuarios.map((u) => (
                  <tr key={u.email}>
                    <td className="py-2 pr-2 text-gray-800">{u.nombre}<div className="text-xs text-gray-400">{u.email}</div></td>
                    {roles.map((r) => {
                      const tiene = asignaciones.some((a) => a.usuario_email.toLowerCase() === u.email.toLowerCase() && a.rol_id === r.id);
                      return <td key={r.id} className="py-2 px-2 text-center"><input type="checkbox" checked={tiene} onChange={() => toggleAsignacion(u.email, r.id, tiene)} className="accent-[#4FAEB2]" /></td>;
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
