"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { ArrowLeft, Loader2, Truck, Printer, Ban, Pencil, X } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Linea = {
  venta_item_id: string;
  producto_id: string;
  producto_nombre: string;
  sku: string | null;
  cantidad_vendida: number;
  cantidad_entregada: number;
  pendiente: number;
};

type Resumen = {
  venta_id: string;
  numero_control: string;
  estado_entrega: string;
  cliente_nombre: string | null;
  numero_orden_compra: string | null;
  lineas: Linea[];
};

type Remision = { id: string; numero: string; estado: string; fecha: string; observacion: string | null; total_items: number };

type LineaEd = Linea & {
  en_esta_remision: number;
  entregado_otras: number;
  max_a_entregar: number;
  observacion: string | null;
};

type Detalle = {
  remision: {
    id: string;
    numero: string;
    estado: string;
    fecha: string;
    numero_control: string;
    numero_orden_compra: string | null;
    cliente_nombre: string | null;
    observacion: string | null;
    usuario_creador_nombre: string | null;
    anulada_motivo: string | null;
  };
  lineas: LineaEd[];
};

// El estado refleja lo REMITIDO (documentado en una nota de remisión), no lo
// que el cliente se llevó del mostrador.
const ESTADO_LABEL: Record<string, string> = {
  pendiente: "Sin remitir",
  parcialmente_entregada: "Remitido parcial",
  entregada: "Remitido",
};
const ESTADO_BADGE: Record<string, string> = {
  pendiente: "bg-slate-100 text-slate-700",
  parcialmente_entregada: "bg-amber-100 text-amber-800",
  entregada: "bg-emerald-100 text-emerald-800",
};

function fmt(n: number): string {
  return Number(n).toLocaleString("es-PY", { maximumFractionDigits: 3 });
}

export default function RemisionesVentaPage() {
  const params = useParams();
  const router = useRouter();
  const ventaId = String(params?.id ?? "");

  const [resumen, setResumen] = useState<Resumen | null>(null);
  const [remisiones, setRemisiones] = useState<Remision[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [guardando, setGuardando] = useState(false);

  // Nueva entrega: cantidad por venta_item_id.
  const [nueva, setNueva] = useState<Record<string, string>>({});
  const [obsNueva, setObsNueva] = useState("");
  // Fecha de la entrega: por defecto hoy, pero se puede remitir una venta de dias atras.
  const [fechaNueva, setFechaNueva] = useState(() => new Date().toISOString().slice(0, 10));

  // Edición de una remisión existente.
  const [detalle, setDetalle] = useState<Detalle | null>(null);
  const [edit, setEdit] = useState<Record<string, string>>({});
  const [obsEdit, setObsEdit] = useState("");
  const [fechaEdit, setFechaEdit] = useState("");
  /** Destinatario: puede diferir del cliente de la venta (entrega a un tercero). */
  const [destinatarioEdit, setDestinatarioEdit] = useState("");

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/ventas/${ventaId}/remisiones`, { cache: "no-store" });
      const j = await res.json();
      if (!res.ok || !j.success) throw new Error(j.error ?? "No se pudo cargar.");
      setResumen(j.data.resumen as Resumen);
      setRemisiones((j.data.remisiones ?? []) as Remision[]);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al cargar.");
    } finally {
      setCargando(false);
    }
  }, [ventaId]);

  useEffect(() => {
    if (ventaId) void cargar();
  }, [ventaId, cargar]);

  const hayPendiente = useMemo(() => (resumen?.lineas ?? []).some((l) => l.pendiente > 0), [resumen]);

  async function crearEntrega() {
    if (!resumen) return;
    const items = resumen.lineas
      .map((l) => ({ venta_item_id: l.venta_item_id, cantidad: Number(nueva[l.venta_item_id] ?? 0) || 0 }))
      .filter((i) => i.cantidad > 0);
    if (items.length === 0) {
      setError("Indicá al menos una cantidad a entregar.");
      return;
    }
    setGuardando(true);
    setError(null);
    setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/ventas/${ventaId}/remisiones`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items, observacion: obsNueva.trim() || null, fecha: fechaNueva || null }),
      });
      const j = await res.json();
      if (!res.ok || !j.success) throw new Error(j.error ?? "No se pudo registrar la entrega.");
      setOk(`Remisión ${j.data.numero} registrada.`);
      setNueva({});
      setObsNueva("");
      setFechaNueva(new Date().toISOString().slice(0, 10));
      await cargar();
      window.open(`/api/ventas/remisiones/${j.data.remision_id}/pdf?auto=1`, "_blank", "noopener");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al registrar.");
    } finally {
      setGuardando(false);
    }
  }

  async function abrirEdicion(id: string) {
    setError(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/ventas/remisiones/${id}`, { cache: "no-store" });
      const j = await res.json();
      if (!res.ok || !j.success) throw new Error(j.error ?? "No se pudo cargar la remisión.");
      const d = j.data as Detalle;
      setDetalle(d);
      setObsEdit(d.remision.observacion ?? "");
      setFechaEdit(String(d.remision.fecha ?? "").slice(0, 10));
      setDestinatarioEdit(d.remision.cliente_nombre ?? "");
      const map: Record<string, string> = {};
      for (const l of d.lineas) map[l.venta_item_id] = String(l.en_esta_remision || "");
      setEdit(map);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al cargar la remisión.");
    }
  }

  async function guardarEdicion() {
    if (!detalle) return;
    setGuardando(true);
    setError(null);
    setOk(null);
    try {
      const items = detalle.lineas.map((l) => ({
        venta_item_id: l.venta_item_id,
        cantidad: Number(edit[l.venta_item_id] ?? 0) || 0,
      }));
      const res = await fetchWithSupabaseSession(`/api/ventas/remisiones/${detalle.remision.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ items, observacion: obsEdit.trim() || null, fecha: fechaEdit || null, cliente_nombre: destinatarioEdit.trim() }),
      });
      const j = await res.json();
      if (!res.ok || !j.success) throw new Error(j.error ?? "No se pudo guardar.");
      setOk(`Remisión ${detalle.remision.numero} actualizada.`);
      setDetalle(null);
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al guardar.");
    } finally {
      setGuardando(false);
    }
  }

  async function anular(id: string, numero: string) {
    const motivo = window.prompt(`Motivo de anulación de ${numero}:`);
    if (motivo === null) return;
    setGuardando(true);
    setError(null);
    setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/ventas/remisiones/${id}/anular`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ motivo: motivo.trim() || null }),
      });
      const j = await res.json();
      if (!res.ok || !j.success) throw new Error(j.error ?? "No se pudo anular.");
      setOk(`Remisión ${numero} anulada. Lo entregado volvió a pendiente.`);
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al anular.");
    } finally {
      setGuardando(false);
    }
  }

  if (cargando) {
    return (
      <div className="flex items-center justify-center py-24 text-slate-500">
        <Loader2 className="h-6 w-6 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-6 p-4 sm:p-6">
      <button
        onClick={() => router.push("/ventas")}
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" /> Volver a ventas
      </button>

      <div className="flex flex-wrap items-center gap-3">
        <Truck className="h-7 w-7 text-[#1E2125]" />
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Entregas · {resumen?.numero_control ?? ""}</h1>
          {resumen && (
            <div className="mt-1 flex flex-wrap items-center gap-2 text-sm">
              <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${ESTADO_BADGE[resumen.estado_entrega] ?? "bg-slate-100"}`}>
                {ESTADO_LABEL[resumen.estado_entrega] ?? resumen.estado_entrega}
              </span>
              {resumen.cliente_nombre ? <span className="text-slate-500">{resumen.cliente_nombre}</span> : null}
              {resumen.numero_orden_compra ? (
                <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-600">
                  OC: {resumen.numero_orden_compra}
                </span>
              ) : null}
            </div>
          )}
        </div>
      </div>

      {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      {/* Nueva entrega */}
      {hayPendiente && (
        <div className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
          <h2 className="mb-1 text-sm font-semibold text-gray-700">Registrar entrega</h2>
          <p className="mb-3 text-xs text-slate-500">
            Poné cuánto le entregás hoy de cada producto. Lo que no entregues queda como pendiente y podés remitirlo después.
          </p>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                  <th className="px-3 py-2 text-left">Producto</th>
                  <th className="px-3 py-2 text-right">Vendido</th>
                  <th className="px-3 py-2 text-right">Entregado</th>
                  <th className="px-3 py-2 text-right">Pendiente</th>
                  <th className="px-3 py-2 text-right">Entregar ahora</th>
                </tr>
              </thead>
              <tbody>
                {(resumen?.lineas ?? []).map((l) => (
                  <tr key={l.venta_item_id} className="border-b border-slate-100">
                    <td className="px-3 py-2">
                      {l.producto_nombre}
                      {l.sku ? <span className="ml-1 text-xs text-slate-400">· {l.sku}</span> : null}
                    </td>
                    <td className="px-3 py-2 text-right tabular-nums">{fmt(l.cantidad_vendida)}</td>
                    <td className="px-3 py-2 text-right tabular-nums text-slate-500">{fmt(l.cantidad_entregada)}</td>
                    <td className="px-3 py-2 text-right tabular-nums font-medium text-amber-700">{fmt(l.pendiente)}</td>
                    <td className="px-3 py-2 text-right">
                      <input
                        type="number"
                        min={0}
                        max={l.pendiente}
                        step="any"
                        disabled={l.pendiente <= 0}
                        value={nueva[l.venta_item_id] ?? ""}
                        onChange={(e) => setNueva((p) => ({ ...p, [l.venta_item_id]: e.target.value }))}
                        placeholder="0"
                        className="w-28 rounded-md border border-slate-300 px-2 py-1 text-right disabled:bg-slate-100"
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-[200px_1fr]">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-600">Fecha de la entrega</label>
              <input
                type="date"
                value={fechaNueva}
                onChange={(e) => setFechaNueva(e.target.value)}
                className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
              />
            </div>
            <div>
            <label className="mb-1 block text-xs font-medium text-slate-600">Observación (opcional)</label>
            <input
              value={obsNueva}
              onChange={(e) => setObsNueva(e.target.value)}
              placeholder="Ej.: falta stock del ítem 2, se entrega la semana próxima"
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
            />
            </div>
          </div>

          <div className="mt-4 flex justify-end gap-2">
            <button
              type="button"
              onClick={() => { setNueva({}); setObsNueva(""); }}
              className="rounded-md border border-slate-300 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50"
            >
              Limpiar
            </button>
            <button
              type="button"
              onClick={crearEntrega}
              disabled={guardando}
              className="inline-flex items-center gap-2 rounded-md bg-[#1E2125] px-4 py-2 text-sm font-medium text-white hover:bg-black disabled:opacity-50"
            >
              {guardando ? <Loader2 className="h-4 w-4 animate-spin" /> : <Truck className="h-4 w-4" />}
              Registrar e imprimir
            </button>
          </div>
        </div>
      )}

      {/* Remisiones emitidas */}
      <div className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
        <h2 className="border-b border-slate-100 px-5 py-3 text-sm font-semibold text-gray-700">Remisiones emitidas</h2>
        {remisiones.length === 0 ? (
          <p className="px-5 py-6 text-sm text-slate-500">Todavía no hay remisiones para esta venta.</p>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                <th className="px-4 py-2 text-left">Número</th>
                <th className="px-4 py-2 text-left">Fecha</th>
                <th className="px-4 py-2 text-left">Estado</th>
                <th className="px-4 py-2 text-right">Ítems</th>
                <th className="px-4 py-2 text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              {remisiones.map((r) => (
                <tr key={r.id} className="border-b border-slate-100">
                  <td className="px-4 py-2 font-mono font-medium text-gray-800">{r.numero}</td>
                  <td className="px-4 py-2 text-slate-600">{new Date(r.fecha).toLocaleDateString("es-PY")}</td>
                  <td className="px-4 py-2">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${r.estado === "anulada" ? "bg-red-100 text-red-700" : "bg-indigo-100 text-indigo-700"}`}>
                      {r.estado === "anulada" ? "Anulada" : "Confirmada"}
                    </span>
                  </td>
                  <td className="px-4 py-2 text-right tabular-nums">{r.total_items}</td>
                  <td className="px-4 py-2">
                    <div className="flex justify-end gap-1">
                      <a
                        href={`/api/ventas/remisiones/${r.id}/pdf?auto=1`}
                        target="_blank"
                        rel="noopener"
                        title="Imprimir"
                        className="rounded p-1.5 text-slate-500 hover:bg-slate-100"
                      >
                        <Printer className="h-4 w-4" />
                      </a>
                      {r.estado !== "anulada" && (
                        <>
                          <button
                            type="button"
                            onClick={() => abrirEdicion(r.id)}
                            title="Editar cantidades"
                            className="rounded p-1.5 text-slate-500 hover:bg-slate-100"
                          >
                            <Pencil className="h-4 w-4" />
                          </button>
                          <button
                            type="button"
                            onClick={() => anular(r.id, r.numero)}
                            title="Anular"
                            className="rounded p-1.5 text-red-500 hover:bg-red-50"
                          >
                            <Ban className="h-4 w-4" />
                          </button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Modal de edición */}
      {detalle && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="max-h-[90vh] w-full max-w-3xl overflow-y-auto rounded-xl bg-white p-6 shadow-xl">
            <div className="mb-4 flex items-start justify-between">
              <div>
                <h3 className="text-lg font-bold text-gray-800">Editar {detalle.remision.numero}</h3>
                <p className="text-xs text-slate-500">
                  Cambiá lo que realmente entregaste. El pendiente de la venta se recalcula solo.
                </p>
              </div>
              <button type="button" onClick={() => setDetalle(null)} className="rounded p-1 text-slate-400 hover:bg-slate-100">
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full min-w-[560px] text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-xs uppercase text-slate-500">
                    <th className="px-3 py-2 text-left">Producto</th>
                    <th className="px-3 py-2 text-right">Vendido</th>
                    <th className="px-3 py-2 text-right">Otras remisiones</th>
                    <th className="px-3 py-2 text-right">Máx.</th>
                    <th className="px-3 py-2 text-right">En esta</th>
                  </tr>
                </thead>
                <tbody>
                  {detalle.lineas.map((l) => (
                    <tr key={l.venta_item_id} className="border-b border-slate-100">
                      <td className="px-3 py-2">{l.producto_nombre}</td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmt(l.cantidad_vendida)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-slate-500">{fmt(l.entregado_otras)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-slate-500">{fmt(l.max_a_entregar)}</td>
                      <td className="px-3 py-2 text-right">
                        <input
                          type="number"
                          min={0}
                          max={l.max_a_entregar}
                          step="any"
                          value={edit[l.venta_item_id] ?? ""}
                          onChange={(e) => setEdit((p) => ({ ...p, [l.venta_item_id]: e.target.value }))}
                          placeholder="0"
                          className="w-28 rounded-md border border-slate-300 px-2 py-1 text-right"
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="mt-3">
              <label className="mb-1 block text-xs font-medium text-slate-600">Destinatario</label>
              <input
                value={destinatarioEdit}
                onChange={(e) => setDestinatarioEdit(e.target.value)}
                placeholder="A nombre de quién se entrega"
                className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
              />
              <p className="mt-1 text-xs text-slate-500">
                Por defecto el cliente de la venta. Cambialo si la mercadería se entrega a un tercero.
              </p>
            </div>
            <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-[200px_1fr]">
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-600">Fecha de la entrega</label>
                <input
                  type="date"
                  value={fechaEdit}
                  onChange={(e) => setFechaEdit(e.target.value)}
                  className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-600">Observación</label>
                <input
                  value={obsEdit}
                  onChange={(e) => setObsEdit(e.target.value)}
                  className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
                />
              </div>
            </div>

            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setDetalle(null)}
                className="rounded-md border border-slate-300 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={guardarEdicion}
                disabled={guardando}
                className="inline-flex items-center gap-2 rounded-md bg-[#1E2125] px-4 py-2 text-sm font-medium text-white hover:bg-black disabled:opacity-50"
              >
                {guardando ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                Guardar cambios
              </button>
            </div>
          </div>
        </div>
      )}

      <p className="text-xs text-slate-400">
        El stock ya salió al registrar la venta, así que estas remisiones no vuelven a moverlo: registran la entrega física.{" "}
        <Link href="/ventas" className="underline">Ver ventas</Link>
      </p>
    </div>
  );
}
