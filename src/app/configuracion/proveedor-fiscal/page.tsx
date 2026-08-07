"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, Landmark, AlertTriangle, Save } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Estado = { ok: boolean; estado: string; mensaje?: string; faltantes?: string[] };
type Cfg = { proveedor_fiscal: string; pais_fiscal: string | null; fiscal_habilitado: boolean; proveedor_estado: Estado };

const PROVEEDORES = [
  { v: "none", l: "Factura comercial interna (sin electrónica)", pais: "—" },
  { v: "sifen_py", l: "SIFEN — Paraguay", pais: "PY" },
  { v: "sin_bo", l: "SIN — Bolivia", pais: "BO" },
];

export default function ProveedorFiscalPage() {
  const [cfg, setCfg] = useState<Cfg | null>(null);
  const [proveedor, setProveedor] = useState("none");
  const [habilitado, setHabilitado] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchWithSupabaseSession("/api/configuracion/proveedor-fiscal", { cache: "no-store" });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo cargar."); return; }
      setCfg(body.data as Cfg);
      setProveedor(body.data.proveedor_fiscal);
      setHabilitado(body.data.fiscal_habilitado);
    } catch { setError("Error de red."); } finally { setLoading(false); }
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  async function guardar() {
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession("/api/configuracion/proveedor-fiscal", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ proveedor_fiscal: proveedor, fiscal_habilitado: proveedor === "sin_bo" ? habilitado : undefined }),
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo guardar."); return; }
      setOk("Configuración fiscal guardada.");
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  if (loading) return <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>;

  return (
    <div className="space-y-6 max-w-3xl">
      <Link href="/configuracion" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a configuración
      </Link>
      <div className="flex items-center gap-3">
        <Landmark className="h-7 w-7 text-[#1E2125]" />
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Facturación electrónica por país</h1>
          <p className="text-sm text-gray-500">Elegí el proveedor fiscal. Paraguay usa el módulo SIFEN existente; Bolivia (SIN) queda detrás de un flag hasta completar credenciales y autorización.</p>
        </div>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5 space-y-4">
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Proveedor fiscal</label>
          <select value={proveedor} onChange={(e) => setProveedor(e.target.value)} className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm bg-white">
            {PROVEEDORES.map((p) => <option key={p.v} value={p.v}>{p.l}</option>)}
          </select>
        </div>

        {proveedor === "sifen_py" && (
          <div className="rounded-md bg-sky-50 border border-sky-200 p-3 text-sm text-sky-800">
            La emisión de Paraguay se gestiona desde el módulo <Link href="/configuracion/facturacion-electronica" className="font-semibold underline">SIFEN existente</Link>.
          </div>
        )}

        {proveedor === "sin_bo" && (
          <>
            <div className="rounded-md bg-amber-50 border border-amber-200 p-3 text-sm text-amber-800 flex items-start gap-2">
              <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
              <div>
                <p className="font-semibold">Bolivia (SIN) no está habilitada para emitir todavía.</p>
                <p className="mt-1">La arquitectura y el almacenamiento seguro están listos, pero la emisión real requiere credenciales, modalidad y autorización del SIN. Requisitos pendientes:</p>
                <ul className="list-disc ml-5 mt-1 space-y-0.5">
                  {(cfg?.proveedor_estado?.faltantes ?? []).map((f, i) => <li key={i}>{f}</li>)}
                </ul>
              </div>
            </div>
            <label className="inline-flex items-center gap-2 text-sm">
              <input type="checkbox" checked={habilitado} onChange={(e) => setHabilitado(e.target.checked)} className="accent-[#1E2125]" />
              Marcar como configurado (no activa emisión real hasta pruebas + autorización)
            </label>
          </>
        )}

        <div className="flex justify-end">
          <button onClick={guardar} disabled={busy} className="inline-flex items-center gap-1.5 rounded-md bg-[#1E2125] px-4 py-2 text-sm font-medium text-white hover:bg-[#17191C] disabled:opacity-50">
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />} Guardar
          </button>
        </div>
      </div>
    </div>
  );
}
