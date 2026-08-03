"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, Plus, Trash2, LogOut, Printer, Ban } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Producto = { id: string; nombre: string; sku: string | null; costo_promedio?: number; unidad_medida?: string | null };
type Item = { producto_id: string; producto_nombre: string; sku: string | null; costo_unitario: number; cantidad: number; observacion: string };
type Nota = { id: string; numero: string; motivo: string; estado: string; fecha: string; usuario_creador_nombre: string | null; total_items: number };

const MOTIVOS: Array<{ v: string; l: string }> = [
  { v: "uso_interno", l: "Uso interno" }, { v: "muestra", l: "Muestra" }, { v: "prestamo", l: "Préstamo" },
  { v: "daño", l: "Daño" }, { v: "perdida", l: "Pérdida" }, { v: "consumo", l: "Consumo" },
  { v: "ajuste", l: "Ajuste" }, { v: "otro", l: "Otro" },
];
const ESTADO_BADGE: Record<string, string> = { borrador: "bg-slate-100 text-slate-700", confirmada: "bg-emerald-100 text-emerald-700", anulada: "bg-red-100 text-red-700" };
const ESTADO_LABEL: Record<string, string> = { borrador: "Borrador", confirmada: "Confirmada", anulada: "Anulada" };
const MOTIVO_LABEL: Record<string, string> = Object.fromEntries(MOTIVOS.map((m) => [m.v, m.l]));
const inputClass = "w-full rounded-md border border-gray-300 px-3 py-2 text-sm";

export default function NotasSalidaPage() {
  const [productos, setProductos] = useState<Producto[]>([]);
  const [notas, setNotas] = useState<Nota[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [motivo, setMotivo] = useState("uso_interno");
  const [observacion, setObservacion] = useState("");
  const [items, setItems] = useState<Item[]>([]);
  const [sel, setSel] = useState("");
  const [mostrarForm, setMostrarForm] = useState(false);

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const [rn, rp] = await Promise.all([
        fetchWithSupabaseSession("/api/notas-salida", { cache: "no-store" }),
        fetchWithSupabaseSession("/api/productos", { cache: "no-store" }),
      ]);
      const bn = await rn.json();
      const bp = await rp.json();
      if (bn?.data?.notas) setNotas(bn.data.notas as Nota[]);
      const list = (bp?.data?.productos ?? []) as Record<string, unknown>[];
      setProductos(list.map((p) => ({ id: String(p.id), nombre: String(p.nombre), sku: (p.sku as string) ?? null, costo_promedio: Number(p.costo_promedio) || 0, unidad_medida: (p.unidad_medida as string) ?? null })));
    } catch {
      setError("Error de red.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void cargar(); }, [cargar]);

  function agregar() {
    const p = productos.find((x) => x.id === sel);
    if (!p || items.some((it) => it.producto_id === p.id)) return;
    setItems((prev) => [...prev, { producto_id: p.id, producto_nombre: p.nombre, sku: p.sku, costo_unitario: p.costo_promedio ?? 0, cantidad: 1, observacion: "" }]);
    setSel("");
  }
  function upd(i: number, patch: Partial<Item>) { setItems((prev) => prev.map((it, idx) => (idx === i ? { ...it, ...patch } : it))); }
  function del(i: number) { setItems((prev) => prev.filter((_, idx) => idx !== i)); }

  async function guardar(confirmar: boolean) {
    if (busy) return;
    const validos = items.filter((it) => it.cantidad > 0);
    if (validos.length === 0) { setError("Agregá al menos un producto con cantidad."); return; }
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession("/api/notas-salida", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ motivo, observacion: observacion.trim() || null, confirmar, items: validos }),
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo guardar."); return; }
      setOk(confirmar ? `Nota ${body.data.numero} confirmada. Stock descontado.` : `Nota ${body.data.numero} guardada en borrador.`);
      setItems([]); setObservacion(""); setMostrarForm(false);
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  async function accion(id: string, a: "confirmar" | "anular") {
    if (busy) return;
    let motivoAnul = "";
    if (a === "anular") { motivoAnul = prompt("Motivo de anulación (repone stock):") ?? ""; if (!motivoAnul.trim()) return; }
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/notas-salida/${id}/${a}`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: a === "anular" ? JSON.stringify({ motivo: motivoAnul }) : undefined,
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo completar."); return; }
      setOk(a === "confirmar" ? "Nota confirmada. Stock descontado." : "Nota anulada. Stock repuesto.");
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  return (
    <div className="space-y-6 max-w-5xl">
      <Link href="/inventario" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a inventario
      </Link>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <LogOut className="h-7 w-7 text-[#4FAEB2]" />
          <div>
            <h1 className="text-2xl font-bold text-gray-800">Notas de salida</h1>
            <p className="text-sm text-gray-500">Salidas de inventario no ligadas a factura. Descuentan stock al confirmar.</p>
          </div>
        </div>
        <button onClick={() => setMostrarForm((v) => !v)} className="inline-flex items-center gap-1.5 rounded-md bg-[#4FAEB2] px-4 py-2 text-sm font-medium text-white hover:bg-[#3F8E91]">
          <Plus className="h-4 w-4" /> Nueva nota de salida
        </button>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      {mostrarForm && (
        <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5 space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Motivo</label>
              <select value={motivo} onChange={(e) => setMotivo(e.target.value)} className={`${inputClass} bg-white`}>
                {MOTIVOS.map((m) => <option key={m.v} value={m.v}>{m.l}</option>)}
              </select>
            </div>
            <div className="sm:col-span-2">
              <label className="block text-xs font-medium text-gray-600 mb-1">Observación</label>
              <input value={observacion} onChange={(e) => setObservacion(e.target.value)} className={inputClass} placeholder="Detalle de la salida (opcional)" />
            </div>
          </div>

          <div className="flex flex-wrap items-end gap-2">
            <div className="flex-1 min-w-[240px]">
              <label className="block text-xs font-medium text-gray-600 mb-1">Agregar producto</label>
              <select value={sel} onChange={(e) => setSel(e.target.value)} className={`${inputClass} bg-white`}>
                <option value="">— Seleccioná un producto —</option>
                {productos.filter((p) => !items.some((it) => it.producto_id === p.id)).map((p) => (
                  <option key={p.id} value={p.id}>{p.nombre}{p.sku ? ` · ${p.sku}` : ""}</option>
                ))}
              </select>
            </div>
            <button type="button" onClick={agregar} disabled={!sel} className="inline-flex items-center gap-1 rounded-md bg-[#4FAEB2] px-3 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50">
              <Plus className="h-4 w-4" /> Agregar
            </button>
          </div>

          {items.length > 0 && (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[560px] text-sm">
                <thead className="text-left text-xs text-gray-500 uppercase">
                  <tr><th className="py-2 pr-2">Producto</th><th className="py-2 px-2 w-28">Cantidad</th><th className="py-2 px-2">Observación</th><th className="py-2 w-10"></th></tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {items.map((it, i) => (
                    <tr key={it.producto_id}>
                      <td className="py-2 pr-2 text-gray-800">{it.producto_nombre}</td>
                      <td className="py-2 px-2"><input type="number" min="0" step="0.01" value={it.cantidad} onChange={(e) => upd(i, { cantidad: Number(e.target.value) })} className={inputClass} /></td>
                      <td className="py-2 px-2"><input value={it.observacion} onChange={(e) => upd(i, { observacion: e.target.value })} className={inputClass} placeholder="Opcional" /></td>
                      <td className="py-2 text-right"><button onClick={() => del(i)} className="text-red-600 hover:text-red-700"><Trash2 className="h-4 w-4" /></button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <div className="flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
            <button onClick={() => guardar(false)} disabled={busy} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50">Guardar borrador</button>
            <button onClick={() => guardar(true)} disabled={busy} className="inline-flex items-center justify-center gap-1.5 rounded-md bg-[#4FAEB2] px-5 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <LogOut className="h-4 w-4" />} Confirmar salida
            </button>
          </div>
        </div>
      )}

      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        {loading ? (
          <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>
        ) : notas.length === 0 ? (
          <p className="text-sm text-gray-500 p-6">No hay notas de salida registradas.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[680px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-gray-500">
                <tr><th className="py-3 px-4 text-left font-medium">N°</th><th className="py-3 px-4 text-left font-medium">Motivo</th><th className="py-3 px-4 text-left font-medium">Fecha</th><th className="py-3 px-4 text-right font-medium">Ítems</th><th className="py-3 px-4 text-center font-medium">Estado</th><th className="py-3 px-4 text-right font-medium">Acciones</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {notas.map((n) => (
                  <tr key={n.id}>
                    <td className="py-2.5 px-4 font-medium text-gray-800">{n.numero}</td>
                    <td className="py-2.5 px-4 text-gray-600">{MOTIVO_LABEL[n.motivo] ?? n.motivo}</td>
                    <td className="py-2.5 px-4 text-gray-600">{new Date(n.fecha).toLocaleDateString("es-PY")}</td>
                    <td className="py-2.5 px-4 text-right tabular-nums">{n.total_items}</td>
                    <td className="py-2.5 px-4 text-center"><span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${ESTADO_BADGE[n.estado] ?? "bg-slate-100"}`}>{ESTADO_LABEL[n.estado] ?? n.estado}</span></td>
                    <td className="py-2.5 px-4 text-right">
                      <div className="inline-flex items-center gap-3">
                        <a href={`/api/notas-salida/${n.id}/pdf?auto=1`} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs font-semibold text-slate-600 hover:underline"><Printer className="h-3.5 w-3.5" /> PDF</a>
                        {n.estado === "borrador" && <button onClick={() => accion(n.id, "confirmar")} disabled={busy} className="text-xs font-semibold text-[#3F8E91] hover:underline disabled:opacity-50">Confirmar</button>}
                        {n.estado === "confirmada" && <button onClick={() => accion(n.id, "anular")} disabled={busy} className="inline-flex items-center gap-1 text-xs font-semibold text-red-700 hover:underline disabled:opacity-50"><Ban className="h-3.5 w-3.5" /> Anular</button>}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
