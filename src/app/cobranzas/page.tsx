"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Plus, Trash2, Save, Phone, MessageSquare, Mail, MapPin, StickyNote, CalendarClock } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Tramo = { nombre: string; dias_desde: number | null; dias_hasta: number | null; color: string | null; activo: boolean };
type ClienteLite = { id: string; nombre: string };
type Promesa = { id: string; fecha_promesa: string; monto: number; observacion: string | null; estado: string; responsable_nombre: string | null };
type Gestion = { id: string; tipo: string; resultado: string | null; observacion: string | null; fecha: string; usuario_nombre: string | null };

const TIPO_GESTION = [
  { v: "llamada", l: "Llamada", icon: Phone }, { v: "whatsapp", l: "WhatsApp", icon: MessageSquare },
  { v: "correo", l: "Correo", icon: Mail }, { v: "visita", l: "Visita", icon: MapPin },
  { v: "nota", l: "Nota interna", icon: StickyNote }, { v: "otro", l: "Otro", icon: StickyNote },
];
const TIPO_ICON: Record<string, typeof Phone> = Object.fromEntries(TIPO_GESTION.map((t) => [t.v, t.icon]));
const TIPO_LABEL: Record<string, string> = Object.fromEntries(TIPO_GESTION.map((t) => [t.v, t.l]));
const PROMESA_BADGE: Record<string, string> = { pendiente: "bg-amber-100 text-amber-700", cumplida: "bg-emerald-100 text-emerald-700", incumplida: "bg-red-100 text-red-700", anulada: "bg-slate-100 text-slate-500" };
const inputClass = "w-full rounded-md border border-gray-300 px-3 py-2 text-sm";

export default function CobranzasPage() {
  const [tab, setTab] = useState<"tramos" | "gestion">("gestion");
  const [tramos, setTramos] = useState<Tramo[]>([]);
  const [clientes, setClientes] = useState<ClienteLite[]>([]);
  const [clienteId, setClienteId] = useState("");
  const [promesas, setPromesas] = useState<Promesa[]>([]);
  const [gestiones, setGestiones] = useState<Gestion[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Formularios
  const [pFecha, setPFecha] = useState("");
  const [pMonto, setPMonto] = useState("");
  const [pObs, setPObs] = useState("");
  const [gTipo, setGTipo] = useState("llamada");
  const [gResultado, setGResultado] = useState("");
  const [gObs, setGObs] = useState("");

  const cargarBase = useCallback(async () => {
    try {
      const [rt, rc] = await Promise.all([
        fetchWithSupabaseSession("/api/cobranzas/tramos", { cache: "no-store" }),
        fetchWithSupabaseSession("/api/clientes", { cache: "no-store" }),
      ]);
      const bt = await rt.json();
      const bc = await rc.json();
      if (bt?.data?.tramos) setTramos(bt.data.tramos as Tramo[]);
      const list = (bc?.data?.clientes ?? bc?.data ?? []) as Record<string, unknown>[];
      setClientes(list.map((c) => ({ id: String(c.id), nombre: String(c.empresa || c.nombre_contacto || c.nombre || "Cliente") })));
    } catch { setError("Error de red al cargar."); }
  }, []);

  const cargarCliente = useCallback(async (cid: string) => {
    if (!cid) { setPromesas([]); setGestiones([]); return; }
    try {
      const [rp, rg] = await Promise.all([
        fetchWithSupabaseSession(`/api/cobranzas/promesas?cliente_id=${cid}`, { cache: "no-store" }),
        fetchWithSupabaseSession(`/api/cobranzas/gestiones?cliente_id=${cid}`, { cache: "no-store" }),
      ]);
      const bp = await rp.json();
      const bg = await rg.json();
      setPromesas((bp?.data?.promesas ?? []) as Promesa[]);
      setGestiones((bg?.data?.gestiones ?? []) as Gestion[]);
    } catch { setError("Error de red."); }
  }, []);

  useEffect(() => { void cargarBase(); }, [cargarBase]);
  useEffect(() => { void cargarCliente(clienteId); }, [clienteId, cargarCliente]);

  function updTramo(i: number, patch: Partial<Tramo>) { setTramos((prev) => prev.map((t, idx) => (idx === i ? { ...t, ...patch } : t))); }
  function addTramo() { setTramos((prev) => [...prev, { nombre: "Nuevo tramo", dias_desde: 0, dias_hasta: null, color: "#64748b", activo: true }]); }
  function delTramo(i: number) { setTramos((prev) => prev.filter((_, idx) => idx !== i)); }

  async function guardarTramos() {
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession("/api/cobranzas/tramos", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ tramos }) });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo guardar."); return; }
      setOk("Tramos guardados.");
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  async function registrarPromesa() {
    if (!clienteId || !pFecha) { setError("Elegí cliente y fecha."); return; }
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession("/api/cobranzas/promesas", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ cliente_id: clienteId, fecha_promesa: pFecha, monto: Number(pMonto) || 0, observacion: pObs.trim() || null }) });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo registrar."); return; }
      setOk("Promesa registrada."); setPFecha(""); setPMonto(""); setPObs("");
      await cargarCliente(clienteId);
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  async function cambiarEstadoPromesa(id: string, estado: string) {
    await fetchWithSupabaseSession(`/api/cobranzas/promesas/${id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ estado }) });
    await cargarCliente(clienteId);
  }

  async function registrarGestion() {
    if (!clienteId) { setError("Elegí un cliente."); return; }
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession("/api/cobranzas/gestiones", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ cliente_id: clienteId, tipo: gTipo, resultado: gResultado.trim() || null, observacion: gObs.trim() || null }) });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo registrar."); return; }
      setOk("Gestión registrada."); setGResultado(""); setGObs("");
      await cargarCliente(clienteId);
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  return (
    <div className="space-y-6 max-w-5xl">
      <Link href="/pagos" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a cobros
      </Link>

      <div className="flex items-center gap-3">
        <CalendarClock className="h-7 w-7 text-[#4FAEB2]" />
        <h1 className="text-2xl font-bold text-gray-800">Cobranzas</h1>
      </div>

      <div className="flex items-center gap-1 border-b border-slate-200">
        <button onClick={() => setTab("gestion")} className={`px-4 py-2 text-sm font-semibold border-b-2 ${tab === "gestion" ? "border-[#4FAEB2] text-[#3F8E91]" : "border-transparent text-slate-500"}`}>Gestión por cliente</button>
        <button onClick={() => setTab("tramos")} className={`px-4 py-2 text-sm font-semibold border-b-2 ${tab === "tramos" ? "border-[#4FAEB2] text-[#3F8E91]" : "border-transparent text-slate-500"}`}>Tramos de cobranza</button>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      {tab === "tramos" && (
        <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5 space-y-3">
          <p className="text-sm text-gray-500">Definí tus propios tramos de aging (días de atraso). Días negativos = próximos a vencer. Dejá &laquo;hasta&raquo; vacío para &laquo;sin límite&raquo;.</p>
          {tramos.map((t, i) => (
            <div key={i} className="flex flex-wrap items-center gap-2">
              <input value={t.color ?? "#64748b"} onChange={(e) => updTramo(i, { color: e.target.value })} type="color" className="h-9 w-9 rounded border border-slate-200" />
              <input value={t.nombre} onChange={(e) => updTramo(i, { nombre: e.target.value })} className={`${inputClass} flex-1 min-w-[160px]`} placeholder="Nombre" />
              <input type="number" value={t.dias_desde ?? ""} onChange={(e) => updTramo(i, { dias_desde: e.target.value === "" ? null : Number(e.target.value) })} className={`${inputClass} w-24`} placeholder="Desde" />
              <input type="number" value={t.dias_hasta ?? ""} onChange={(e) => updTramo(i, { dias_hasta: e.target.value === "" ? null : Number(e.target.value) })} className={`${inputClass} w-24`} placeholder="Hasta" />
              <button onClick={() => delTramo(i)} className="text-red-600 hover:text-red-700"><Trash2 className="h-4 w-4" /></button>
            </div>
          ))}
          <div className="flex justify-between pt-2">
            <button onClick={addTramo} className="inline-flex items-center gap-1 text-sm font-semibold text-[#3F8E91] hover:underline"><Plus className="h-4 w-4" /> Agregar tramo</button>
            <button onClick={guardarTramos} disabled={busy} className="inline-flex items-center gap-1.5 rounded-md bg-[#4FAEB2] px-4 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50"><Save className="h-4 w-4" /> Guardar tramos</button>
          </div>
        </div>
      )}

      {tab === "gestion" && (
        <>
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">Cliente</label>
            <select value={clienteId} onChange={(e) => setClienteId(e.target.value)} className={`${inputClass} bg-white max-w-md`}>
              <option value="">— Seleccioná un cliente —</option>
              {clientes.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}
            </select>
          </div>

          {clienteId && (
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {/* Promesas */}
              <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5 space-y-3">
                <h2 className="text-sm font-semibold text-gray-700">Promesas de pago</h2>
                <div className="flex flex-wrap gap-2">
                  <input type="date" value={pFecha} onChange={(e) => setPFecha(e.target.value)} className={`${inputClass} w-40`} />
                  <input type="number" value={pMonto} onChange={(e) => setPMonto(e.target.value)} className={`${inputClass} w-32`} placeholder="Monto" />
                  <input value={pObs} onChange={(e) => setPObs(e.target.value)} className={`${inputClass} flex-1 min-w-[120px]`} placeholder="Observación" />
                  <button onClick={registrarPromesa} disabled={busy} className="rounded-md bg-[#4FAEB2] px-3 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50">Registrar</button>
                </div>
                <div className="divide-y divide-slate-100">
                  {promesas.length === 0 ? <p className="text-sm text-gray-400 py-2">Sin promesas.</p> : promesas.map((p) => (
                    <div key={p.id} className="py-2 flex items-center justify-between gap-2 text-sm">
                      <div>
                        <div className="font-medium text-gray-800">{new Date(p.fecha_promesa).toLocaleDateString("es-PY")} · Gs. {Number(p.monto).toLocaleString("es-PY")}</div>
                        {p.observacion && <div className="text-xs text-gray-500">{p.observacion}</div>}
                      </div>
                      <div className="flex items-center gap-2">
                        <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${PROMESA_BADGE[p.estado] ?? "bg-slate-100"}`}>{p.estado}</span>
                        {p.estado === "pendiente" && (
                          <select onChange={(e) => e.target.value && cambiarEstadoPromesa(p.id, e.target.value)} defaultValue="" className="text-xs border border-slate-200 rounded px-1 py-0.5">
                            <option value="">…</option>
                            <option value="cumplida">Cumplida</option>
                            <option value="incumplida">Incumplida</option>
                            <option value="anulada">Anular</option>
                          </select>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Gestiones */}
              <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5 space-y-3">
                <h2 className="text-sm font-semibold text-gray-700">Gestiones de cobranza</h2>
                <div className="space-y-2">
                  <div className="flex flex-wrap gap-2">
                    <select value={gTipo} onChange={(e) => setGTipo(e.target.value)} className={`${inputClass} bg-white w-40`}>
                      {TIPO_GESTION.map((t) => <option key={t.v} value={t.v}>{t.l}</option>)}
                    </select>
                    <input value={gResultado} onChange={(e) => setGResultado(e.target.value)} className={`${inputClass} flex-1 min-w-[120px]`} placeholder="Resultado" />
                  </div>
                  <div className="flex gap-2">
                    <input value={gObs} onChange={(e) => setGObs(e.target.value)} className={`${inputClass} flex-1`} placeholder="Observación" />
                    <button onClick={registrarGestion} disabled={busy} className="rounded-md bg-[#4FAEB2] px-3 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50">Registrar</button>
                  </div>
                </div>
                <div className="divide-y divide-slate-100">
                  {gestiones.length === 0 ? <p className="text-sm text-gray-400 py-2">Sin gestiones.</p> : gestiones.map((g) => {
                    const Icon = TIPO_ICON[g.tipo] ?? StickyNote;
                    return (
                      <div key={g.id} className="py-2 flex items-start gap-2 text-sm">
                        <Icon className="h-4 w-4 text-[#4FAEB2] mt-0.5 shrink-0" />
                        <div className="flex-1">
                          <div className="font-medium text-gray-800">{TIPO_LABEL[g.tipo] ?? g.tipo}{g.resultado ? ` · ${g.resultado}` : ""}</div>
                          {g.observacion && <div className="text-xs text-gray-500">{g.observacion}</div>}
                          <div className="text-[11px] text-gray-400">{new Date(g.fecha).toLocaleString("es-PY")}{g.usuario_nombre ? ` · ${g.usuario_nombre}` : ""}</div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
