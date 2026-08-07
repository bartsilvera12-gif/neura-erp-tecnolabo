"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { ArrowLeft, Loader2, Truck, Printer, Ban } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Linea = { factura_item_id: string; producto_id: string; producto_nombre: string; sku: string | null; cantidad_facturada: number; cantidad_entregada: number; disponible: number; costo_unitario: number };
type Resumen = { factura_id: string; numero_factura: string; estado_entrega: string; lineas: Linea[] };
type Remision = { id: string; numero: string; estado: string; fecha: string; total_items: number };

const ESTADO_BADGE: Record<string, string> = {
  pendiente: "bg-slate-100 text-slate-700", parcialmente_entregada: "bg-amber-100 text-amber-700", entregada: "bg-emerald-100 text-emerald-700",
  borrador: "bg-slate-100 text-slate-700", confirmada: "bg-emerald-100 text-emerald-700", anulada: "bg-red-100 text-red-700",
};
const ESTADO_LABEL: Record<string, string> = {
  pendiente: "Pendiente", parcialmente_entregada: "Parcialmente entregada", entregada: "Entregada",
  borrador: "Borrador", confirmada: "Confirmada", anulada: "Anulada",
};
const inputClass = "w-full rounded-md border border-gray-300 px-3 py-2 text-sm";

export default function RemisionesFacturaPage() {
  const params = useParams<{ id: string }>();
  const facturaId = params.id;
  const [resumen, setResumen] = useState<Resumen | null>(null);
  const [remisiones, setRemisiones] = useState<Remision[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [cantidades, setCantidades] = useState<Record<string, string>>({});
  const [observacion, setObservacion] = useState("");

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchWithSupabaseSession(`/api/facturas/${facturaId}/remisiones`, { cache: "no-store" });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudieron cargar las remisiones."); return; }
      setResumen(body.data.resumen as Resumen);
      setRemisiones((body.data.remisiones ?? []) as Remision[]);
    } catch { setError("Error de red."); } finally { setLoading(false); }
  }, [facturaId]);

  useEffect(() => { void cargar(); }, [cargar]);

  const hayDisponible = useMemo(() => (resumen?.lineas ?? []).some((l) => l.disponible > 0), [resumen]);

  async function crear(confirmar: boolean) {
    if (busy || !resumen) return;
    const items = resumen.lineas
      .map((l) => ({ factura_item_id: l.factura_item_id, producto_id: l.producto_id, producto_nombre: l.producto_nombre, sku: l.sku, costo_unitario: l.costo_unitario, cantidad: Number(cantidades[l.factura_item_id] ?? "0") || 0 }))
      .filter((it) => it.cantidad > 0);
    if (items.length === 0) { setError("Ingresá al menos una cantidad a remitir."); return; }
    for (const it of items) {
      const l = resumen.lineas.find((x) => x.factura_item_id === it.factura_item_id)!;
      if (it.cantidad > l.disponible) { setError(`No podés remitir ${it.cantidad} de "${l.producto_nombre}" (disponible ${l.disponible}).`); return; }
    }
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/facturas/${facturaId}/remisiones`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items, observacion: observacion.trim() || null, confirmar }),
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo crear la remisión."); return; }
      setOk(confirmar ? `Remisión ${body.data.numero} confirmada. Stock descontado.` : `Remisión ${body.data.numero} en borrador.`);
      setCantidades({}); setObservacion("");
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  async function accion(id: string, a: "confirmar" | "anular") {
    if (busy) return;
    let motivo = "";
    if (a === "anular") { motivo = prompt("Motivo de anulación (repone stock y entregado):") ?? ""; if (!motivo.trim()) return; }
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/remisiones/${id}/${a}`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: a === "anular" ? JSON.stringify({ motivo }) : undefined,
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo completar."); return; }
      setOk(a === "confirmar" ? "Remisión confirmada. Stock descontado." : "Remisión anulada. Stock repuesto.");
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  if (loading) return <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>;

  return (
    <div className="space-y-6 max-w-5xl">
      <Link href={`/facturas/${facturaId}`} className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a la factura
      </Link>

      <div className="flex flex-wrap items-center gap-3">
        <Truck className="h-7 w-7 text-[#1E2125]" />
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Remisiones · {resumen?.numero_factura ?? ""}</h1>
          {resumen && (
            <div className="mt-1 text-sm">
              <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${ESTADO_BADGE[resumen.estado_entrega] ?? "bg-slate-100"}`}>
                {ESTADO_LABEL[resumen.estado_entrega] ?? resumen.estado_entrega}
              </span>
            </div>
          )}
        </div>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      {resumen && hayDisponible && (
        <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
          <h2 className="text-sm font-semibold text-gray-700 mb-3">Nueva remisión</h2>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead className="text-left text-xs text-gray-500 uppercase">
                <tr>
                  <th className="py-2 pr-2">Producto</th>
                  <th className="py-2 px-2 w-24 text-right">Facturado</th>
                  <th className="py-2 px-2 w-24 text-right">Remitido</th>
                  <th className="py-2 px-2 w-28 text-right">Disponible</th>
                  <th className="py-2 px-2 w-28">Remitir ahora</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {resumen.lineas.map((l) => (
                  <tr key={l.factura_item_id}>
                    <td className="py-2 pr-2 text-gray-800">{l.producto_nombre}</td>
                    <td className="py-2 px-2 text-right tabular-nums">{l.cantidad_facturada}</td>
                    <td className="py-2 px-2 text-right tabular-nums">{l.cantidad_entregada}</td>
                    <td className="py-2 px-2 text-right tabular-nums font-medium">{l.disponible}</td>
                    <td className="py-2 px-2">
                      <input type="number" min="0" max={l.disponible} step="0.01" disabled={l.disponible <= 0}
                        value={cantidades[l.factura_item_id] ?? ""}
                        onChange={(e) => setCantidades((p) => ({ ...p, [l.factura_item_id]: e.target.value }))}
                        className={inputClass} placeholder="0" />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-3">
            <label className="block text-xs font-medium text-gray-600 mb-1">Observación</label>
            <input value={observacion} onChange={(e) => setObservacion(e.target.value)} className={inputClass} placeholder="Notas de la entrega (opcional)" />
          </div>
          <div className="mt-4 flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
            <button onClick={() => crear(false)} disabled={busy} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50">Guardar borrador</button>
            <button onClick={() => crear(true)} disabled={busy} className="inline-flex items-center justify-center gap-1.5 rounded-md bg-[#1E2125] px-5 py-2 text-sm font-medium text-white hover:bg-[#17191C] disabled:opacity-50">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Truck className="h-4 w-4" />} Confirmar remisión
            </button>
          </div>
        </div>
      )}

      {resumen && !hayDisponible && (
        <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">Esta factura ya fue entregada por completo.</div>
      )}

      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <h2 className="text-sm font-semibold text-gray-700 p-5 pb-2">Remisiones de la factura</h2>
        {remisiones.length === 0 ? (
          <p className="text-sm text-gray-500 px-5 pb-5">Aún no hay remisiones para esta factura.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[600px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-gray-500">
                <tr><th className="py-3 px-4 text-left font-medium">N°</th><th className="py-3 px-4 text-left font-medium">Fecha</th><th className="py-3 px-4 text-right font-medium">Ítems</th><th className="py-3 px-4 text-center font-medium">Estado</th><th className="py-3 px-4 text-right font-medium">Acciones</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {remisiones.map((r) => (
                  <tr key={r.id}>
                    <td className="py-2.5 px-4 font-medium text-gray-800">{r.numero}</td>
                    <td className="py-2.5 px-4 text-gray-600">{new Date(r.fecha).toLocaleDateString("es-PY")}</td>
                    <td className="py-2.5 px-4 text-right tabular-nums">{r.total_items}</td>
                    <td className="py-2.5 px-4 text-center"><span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${ESTADO_BADGE[r.estado] ?? "bg-slate-100"}`}>{ESTADO_LABEL[r.estado] ?? r.estado}</span></td>
                    <td className="py-2.5 px-4 text-right">
                      <div className="inline-flex items-center gap-3">
                        <a href={`/api/remisiones/${r.id}/pdf?auto=1`} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs font-semibold text-slate-600 hover:underline"><Printer className="h-3.5 w-3.5" /> PDF</a>
                        {r.estado === "borrador" && <button onClick={() => accion(r.id, "confirmar")} disabled={busy} className="text-xs font-semibold text-[#17191C] hover:underline disabled:opacity-50">Confirmar</button>}
                        {r.estado === "confirmada" && <button onClick={() => accion(r.id, "anular")} disabled={busy} className="inline-flex items-center gap-1 text-xs font-semibold text-red-700 hover:underline disabled:opacity-50"><Ban className="h-3.5 w-3.5" /> Anular</button>}
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
