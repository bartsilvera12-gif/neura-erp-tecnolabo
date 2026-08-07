"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { ArrowLeft, Loader2, PackageCheck, Printer, Ban } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Linea = {
  compra_id: string;
  producto_id: string;
  producto_nombre: string;
  sku: string | null;
  cantidad: number;
  cantidad_recibida: number;
  pendiente: number;
  costo_unitario: number;
  estado: string;
};
type Resumen = {
  numero_control: string;
  proveedor_nombre: string | null;
  moneda: string;
  estado_agregado: string;
  lineas: Linea[];
};
type Recepcion = {
  id: string;
  numero: string;
  estado: string;
  fecha: string;
  proveedor_nombre: string | null;
  total_recibido: number;
};

const ESTADO_BADGE: Record<string, string> = {
  registrada: "bg-slate-100 text-slate-700",
  parcialmente_recibida: "bg-amber-100 text-amber-700",
  recibida: "bg-emerald-100 text-emerald-700",
  cancelada: "bg-red-100 text-red-700",
  borrador: "bg-slate-100 text-slate-700",
  confirmada: "bg-emerald-100 text-emerald-700",
  anulada: "bg-red-100 text-red-700",
};
const ESTADO_LABEL: Record<string, string> = {
  registrada: "Registrada",
  parcialmente_recibida: "Parcialmente recibida",
  recibida: "Recibida",
  cancelada: "Cancelada",
  borrador: "Borrador",
  confirmada: "Confirmada",
  anulada: "Anulada",
};

const inputClass = "w-full rounded-md border border-gray-300 px-3 py-2 text-sm";

export default function RecepcionesCompraPage() {
  const params = useParams<{ numero_control: string }>();
  const numeroControl = decodeURIComponent(params.numero_control);

  const [resumen, setResumen] = useState<Resumen | null>(null);
  const [recepciones, setRecepciones] = useState<Recepcion[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [cantidades, setCantidades] = useState<Record<string, string>>({});
  const [rechazos, setRechazos] = useState<Record<string, string>>({});
  const [observacion, setObservacion] = useState("");

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchWithSupabaseSession(`/api/compras/${encodeURIComponent(numeroControl)}/recepciones`, { cache: "no-store" });
      const body = await res.json();
      if (!res.ok || body?.success === false) {
        setError(body?.error ?? "No se pudieron cargar las recepciones.");
        return;
      }
      setResumen(body.data.resumen as Resumen);
      setRecepciones((body.data.recepciones ?? []) as Recepcion[]);
    } catch {
      setError("Error de red.");
    } finally {
      setLoading(false);
    }
  }, [numeroControl]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  const hayPendiente = useMemo(() => (resumen?.lineas ?? []).some((l) => l.pendiente > 0), [resumen]);

  async function registrar(confirmar: boolean) {
    if (busy || !resumen) return;
    const items = resumen.lineas
      .map((l) => ({
        compra_id: l.compra_id,
        producto_id: l.producto_id,
        producto_nombre: l.producto_nombre,
        sku: l.sku,
        costo_unitario: l.costo_unitario,
        cantidad_recibida: Number(cantidades[l.compra_id] ?? "0") || 0,
        cantidad_rechazada: Number(rechazos[l.compra_id] ?? "0") || 0,
      }))
      .filter((it) => it.cantidad_recibida > 0);
    if (items.length === 0) {
      setError("Ingresá al menos una cantidad recibida.");
      return;
    }
    // Validación de excedente en el front (backend igual valida).
    for (const it of items) {
      const linea = resumen.lineas.find((l) => l.compra_id === it.compra_id)!;
      if (it.cantidad_recibida > linea.pendiente) {
        setError(`No podés recibir ${it.cantidad_recibida} de "${linea.producto_nombre}" (pendiente ${linea.pendiente}).`);
        return;
      }
    }
    setBusy(true);
    setError(null);
    setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/compras/${encodeURIComponent(numeroControl)}/recepciones`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items, observacion: observacion.trim() || null, confirmar }),
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) {
        setError(body?.error ?? "No se pudo registrar la recepción.");
        return;
      }
      setOk(confirmar ? `Recepción ${body.data.numero} confirmada. Stock actualizado.` : `Recepción ${body.data.numero} guardada en borrador.`);
      setCantidades({});
      setRechazos({});
      setObservacion("");
      await cargar();
    } catch {
      setError("Error de red al registrar la recepción.");
    } finally {
      setBusy(false);
    }
  }

  async function accionRecepcion(id: string, accion: "confirmar" | "anular") {
    if (busy) return;
    let motivo = "";
    if (accion === "anular") {
      motivo = prompt("Motivo de la anulación (repone stock):") ?? "";
      if (!motivo.trim()) return;
    }
    setBusy(true);
    setError(null);
    setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/compras/recepciones/${id}/${accion}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: accion === "anular" ? JSON.stringify({ motivo }) : undefined,
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) {
        setError(body?.error ?? "No se pudo completar la acción.");
        return;
      }
      setOk(accion === "confirmar" ? "Recepción confirmada. Stock actualizado." : "Recepción anulada. Stock repuesto.");
      await cargar();
    } catch {
      setError("Error de red.");
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>;
  }

  return (
    <div className="space-y-6 max-w-5xl">
      <Link href="/compras" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a compras
      </Link>

      <div className="flex flex-wrap items-center gap-3">
        <PackageCheck className="h-7 w-7 text-[#1E2125]" />
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Recepciones · {numeroControl}</h1>
          {resumen && (
            <div className="mt-1 text-sm text-gray-500">
              {resumen.proveedor_nombre ?? "—"} ·{" "}
              <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${ESTADO_BADGE[resumen.estado_agregado] ?? "bg-slate-100"}`}>
                {ESTADO_LABEL[resumen.estado_agregado] ?? resumen.estado_agregado}
              </span>
            </div>
          )}
        </div>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      {/* Registrar recepción */}
      {resumen && hayPendiente && (
        <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
          <h2 className="text-sm font-semibold text-gray-700 mb-3">Registrar recepción</h2>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] text-sm">
              <thead className="text-left text-xs text-gray-500 uppercase">
                <tr>
                  <th className="py-2 pr-2">Producto</th>
                  <th className="py-2 px-2 w-24 text-right">Comprado</th>
                  <th className="py-2 px-2 w-24 text-right">Recibido</th>
                  <th className="py-2 px-2 w-24 text-right">Pendiente</th>
                  <th className="py-2 px-2 w-28">Recibir ahora</th>
                  <th className="py-2 px-2 w-28">Rechazado</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {resumen.lineas.map((l) => (
                  <tr key={l.compra_id}>
                    <td className="py-2 pr-2 text-gray-800">{l.producto_nombre}</td>
                    <td className="py-2 px-2 text-right tabular-nums">{l.cantidad}</td>
                    <td className="py-2 px-2 text-right tabular-nums">{l.cantidad_recibida}</td>
                    <td className="py-2 px-2 text-right tabular-nums font-medium">{l.pendiente}</td>
                    <td className="py-2 px-2">
                      <input
                        type="number" min="0" max={l.pendiente} step="0.01" disabled={l.pendiente <= 0}
                        value={cantidades[l.compra_id] ?? ""}
                        onChange={(e) => setCantidades((p) => ({ ...p, [l.compra_id]: e.target.value }))}
                        className={inputClass} placeholder="0"
                      />
                    </td>
                    <td className="py-2 px-2">
                      <input
                        type="number" min="0" step="0.01" disabled={l.pendiente <= 0}
                        value={rechazos[l.compra_id] ?? ""}
                        onChange={(e) => setRechazos((p) => ({ ...p, [l.compra_id]: e.target.value }))}
                        className={inputClass} placeholder="0"
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="mt-3">
            <label className="block text-xs font-medium text-gray-600 mb-1">Observación</label>
            <input value={observacion} onChange={(e) => setObservacion(e.target.value)} className={inputClass} placeholder="Notas de la recepción (opcional)" />
          </div>
          <div className="mt-4 flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
            <button onClick={() => registrar(false)} disabled={busy} className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50">
              Guardar borrador
            </button>
            <button onClick={() => registrar(true)} disabled={busy} className="inline-flex items-center justify-center gap-1.5 rounded-md bg-[#1E2125] px-5 py-2 text-sm font-medium text-white hover:bg-[#17191C] disabled:opacity-50">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <PackageCheck className="h-4 w-4" />} Confirmar recepción
            </button>
          </div>
        </div>
      )}

      {resumen && !hayPendiente && (
        <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">Esta compra ya fue recibida en su totalidad.</div>
      )}

      {/* Recepciones existentes */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <h2 className="text-sm font-semibold text-gray-700 p-5 pb-2">Recepciones registradas</h2>
        {recepciones.length === 0 ? (
          <p className="text-sm text-gray-500 px-5 pb-5">Aún no hay recepciones para esta compra.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-gray-500">
                <tr>
                  <th className="py-3 px-4 text-left font-medium">N°</th>
                  <th className="py-3 px-4 text-left font-medium">Fecha</th>
                  <th className="py-3 px-4 text-right font-medium">Recibido</th>
                  <th className="py-3 px-4 text-center font-medium">Estado</th>
                  <th className="py-3 px-4 text-right font-medium">Acciones</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {recepciones.map((r) => (
                  <tr key={r.id}>
                    <td className="py-2.5 px-4 font-medium text-gray-800">{r.numero}</td>
                    <td className="py-2.5 px-4 text-gray-600">{new Date(r.fecha).toLocaleDateString("es-PY")}</td>
                    <td className="py-2.5 px-4 text-right tabular-nums">{Number(r.total_recibido).toLocaleString("es-PY")}</td>
                    <td className="py-2.5 px-4 text-center">
                      <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${ESTADO_BADGE[r.estado] ?? "bg-slate-100"}`}>
                        {ESTADO_LABEL[r.estado] ?? r.estado}
                      </span>
                    </td>
                    <td className="py-2.5 px-4 text-right">
                      <div className="inline-flex items-center gap-3">
                        <a href={`/api/compras/recepciones/${r.id}/pdf?auto=1`} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs font-semibold text-slate-600 hover:underline">
                          <Printer className="h-3.5 w-3.5" /> PDF
                        </a>
                        {r.estado === "borrador" && (
                          <button onClick={() => accionRecepcion(r.id, "confirmar")} disabled={busy} className="text-xs font-semibold text-[#17191C] hover:underline disabled:opacity-50">
                            Confirmar
                          </button>
                        )}
                        {r.estado === "confirmada" && (
                          <button onClick={() => accionRecepcion(r.id, "anular")} disabled={busy} className="inline-flex items-center gap-1 text-xs font-semibold text-red-700 hover:underline disabled:opacity-50">
                            <Ban className="h-3.5 w-3.5" /> Anular
                          </button>
                        )}
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
