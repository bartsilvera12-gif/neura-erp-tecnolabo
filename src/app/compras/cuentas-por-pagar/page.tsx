"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, Wallet, X } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type PagoRow = { id: string; fecha_pago: string; monto: number; metodo_pago: string; referencia: string | null; observacion: string | null; anulado_at: string | null };

type Cxp = {
  id: string;
  proveedor_nombre: string | null;
  compra_numero_control: string | null;
  moneda: string;
  total: number;
  saldo: number;
  fecha_emision: string;
  fecha_vencimiento: string | null;
  estado: string;
  dias_atraso: number;
};

const ESTADO_BADGE: Record<string, string> = {
  pendiente: "bg-amber-100 text-amber-700",
  parcial: "bg-sky-100 text-sky-700",
  pagado: "bg-emerald-100 text-emerald-700",
  anulado: "bg-red-100 text-red-700",
};

function fmt(n: number, moneda: string) {
  return (moneda === "USD" ? "USD " : "Gs. ") + (Number(n) || 0).toLocaleString("es-PY", { maximumFractionDigits: moneda === "USD" ? 2 : 0 });
}

export default function CuentasPorPagarPage() {
  const [cuentas, setCuentas] = useState<Cxp[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [filtroEstado, setFiltroEstado] = useState("");
  const [pagarCuenta, setPagarCuenta] = useState<Cxp | null>(null);
  const [pagos, setPagos] = useState<PagoRow[]>([]);
  const [montoPago, setMontoPago] = useState("");
  const [metodoPago, setMetodoPago] = useState("efectivo");
  const [refPago, setRefPago] = useState("");
  const [busy, setBusy] = useState(false);

  const abrirPago = useCallback(async (c: Cxp) => {
    setPagarCuenta(c);
    setMontoPago(String(c.saldo));
    setMetodoPago("efectivo");
    setRefPago("");
    try {
      const res = await fetchWithSupabaseSession(`/api/cuentas-por-pagar/${c.id}/pagos`, { cache: "no-store" });
      const body = await res.json();
      setPagos((body?.data?.pagos ?? []) as PagoRow[]);
    } catch { setPagos([]); }
  }, []);

  async function registrarPago() {
    if (!pagarCuenta || busy) return;
    setBusy(true); setError(null); setOk(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/cuentas-por-pagar/${pagarCuenta.id}/pagos`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Idempotency-Key": `${pagarCuenta.id}:${montoPago}:${Date.now()}` },
        body: JSON.stringify({ monto: Number(montoPago) || 0, metodo_pago: metodoPago, referencia: refPago.trim() || null }),
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo registrar el pago."); return; }
      setOk("Pago registrado.");
      setPagarCuenta(null);
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  async function anularPago(pagoId: string) {
    const motivo = prompt("Motivo de anulación del pago:") ?? "";
    if (!motivo.trim() || !pagarCuenta) return;
    setBusy(true);
    try {
      const res = await fetchWithSupabaseSession(`/api/cuentas-por-pagar/pagos/${pagoId}/anular`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ motivo }),
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) { setError(body?.error ?? "No se pudo anular."); return; }
      await abrirPago(pagarCuenta);
      await cargar();
    } catch { setError("Error de red."); } finally { setBusy(false); }
  }

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const qs = filtroEstado ? `?estado=${encodeURIComponent(filtroEstado)}` : "";
      const res = await fetchWithSupabaseSession(`/api/cuentas-por-pagar${qs}`, { cache: "no-store" });
      const body = await res.json();
      if (!res.ok || body?.success === false) {
        setError(body?.error ?? "No se pudieron cargar las cuentas por pagar.");
        return;
      }
      setCuentas((body.data.cuentas ?? []) as Cxp[]);
    } catch {
      setError("Error de red.");
    } finally {
      setLoading(false);
    }
  }, [filtroEstado]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  const totalSaldo = cuentas.reduce((s, c) => s + (Number(c.saldo) || 0), 0);

  return (
    <div className="space-y-6 max-w-5xl">
      <Link href="/compras" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a compras
      </Link>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Wallet className="h-7 w-7 text-[#4FAEB2]" />
          <div>
            <h1 className="text-2xl font-bold text-gray-800">Cuentas por pagar</h1>
            <p className="text-sm text-gray-500">Saldo total pendiente: <span className="font-semibold tabular-nums">{fmt(totalSaldo, "PYG")}</span></p>
          </div>
        </div>
        <select value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value)} className="rounded-md border border-gray-300 px-3 py-2 text-sm bg-white">
          <option value="">Todos los estados</option>
          <option value="pendiente">Pendiente</option>
          <option value="parcial">Parcial</option>
          <option value="pagado">Pagado</option>
          <option value="anulado">Anulado</option>
        </select>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}
      {ok && <div className="rounded-md bg-emerald-50 border border-emerald-200 p-3 text-sm text-emerald-700">✓ {ok}</div>}

      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        {loading ? (
          <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>
        ) : cuentas.length === 0 ? (
          <p className="text-sm text-gray-500 p-6">No hay cuentas por pagar registradas. Se generan al registrar compras a crédito.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-gray-500">
                <tr>
                  <th className="py-3 px-4 text-left font-medium">Proveedor</th>
                  <th className="py-3 px-4 text-left font-medium">Compra</th>
                  <th className="py-3 px-4 text-left font-medium">Vencimiento</th>
                  <th className="py-3 px-4 text-right font-medium">Total</th>
                  <th className="py-3 px-4 text-right font-medium">Saldo</th>
                  <th className="py-3 px-4 text-center font-medium">Atraso</th>
                  <th className="py-3 px-4 text-center font-medium">Estado</th>
                  <th className="py-3 px-4 text-right font-medium"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {cuentas.map((c) => (
                  <tr key={c.id}>
                    <td className="py-2.5 px-4 text-gray-800">{c.proveedor_nombre ?? "—"}</td>
                    <td className="py-2.5 px-4">
                      {c.compra_numero_control ? (
                        <Link href={`/compras/${encodeURIComponent(c.compra_numero_control)}/recepciones`} className="text-[#3F8E91] hover:underline">
                          {c.compra_numero_control}
                        </Link>
                      ) : "—"}
                    </td>
                    <td className="py-2.5 px-4 text-gray-600">{c.fecha_vencimiento ? new Date(c.fecha_vencimiento).toLocaleDateString("es-PY") : "—"}</td>
                    <td className="py-2.5 px-4 text-right tabular-nums">{fmt(c.total, c.moneda)}</td>
                    <td className="py-2.5 px-4 text-right tabular-nums font-medium">{fmt(c.saldo, c.moneda)}</td>
                    <td className="py-2.5 px-4 text-center tabular-nums">{c.dias_atraso > 0 ? <span className="text-red-600 font-semibold">{c.dias_atraso}d</span> : "—"}</td>
                    <td className="py-2.5 px-4 text-center">
                      <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${ESTADO_BADGE[c.estado] ?? "bg-slate-100"}`}>{c.estado}</span>
                    </td>
                    <td className="py-2.5 px-4 text-right">
                      {c.estado !== "pagado" && c.estado !== "anulado" && (
                        <button onClick={() => abrirPago(c)} className="text-xs font-semibold text-[#3F8E91] hover:underline">Registrar pago</button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Modal de pago */}
      {pagarCuenta && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setPagarCuenta(null)}>
          <div className="w-full max-w-lg rounded-xl bg-white shadow-xl p-5 space-y-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-bold text-gray-800">Pago a proveedor</h3>
              <button onClick={() => setPagarCuenta(null)} className="text-slate-400 hover:text-slate-600"><X className="h-5 w-5" /></button>
            </div>
            <p className="text-sm text-gray-500">{pagarCuenta.proveedor_nombre ?? "—"} · Saldo {fmt(pagarCuenta.saldo, pagarCuenta.moneda)}</p>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Monto</label>
                <input type="number" min="0" step="1" value={montoPago} onChange={(e) => setMontoPago(e.target.value)} className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm" />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600 mb-1">Método</label>
                <select value={metodoPago} onChange={(e) => setMetodoPago(e.target.value)} className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm bg-white">
                  <option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option><option value="tarjeta">Tarjeta</option><option value="cheque">Cheque</option><option value="otro">Otro</option>
                </select>
              </div>
              <div className="col-span-2">
                <label className="block text-xs font-medium text-gray-600 mb-1">Referencia</label>
                <input value={refPago} onChange={(e) => setRefPago(e.target.value)} className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm" placeholder="N° comprobante, transferencia…" />
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => setPagarCuenta(null)} className="rounded-md border border-slate-300 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50">Cancelar</button>
              <button onClick={registrarPago} disabled={busy} className="inline-flex items-center gap-1.5 rounded-md bg-[#4FAEB2] px-4 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50">{busy ? <Loader2 className="h-4 w-4 animate-spin" /> : null} Registrar pago</button>
            </div>
            {pagos.length > 0 && (
              <div className="border-t border-slate-100 pt-3">
                <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Historial de pagos</h4>
                <div className="divide-y divide-slate-100 max-h-48 overflow-y-auto">
                  {pagos.map((p) => (
                    <div key={p.id} className={`py-1.5 flex items-center justify-between text-sm ${p.anulado_at ? "opacity-50 line-through" : ""}`}>
                      <span>{new Date(p.fecha_pago).toLocaleDateString("es-PY")} · {fmt(p.monto, pagarCuenta.moneda)} · {p.metodo_pago}</span>
                      {!p.anulado_at && <button onClick={() => anularPago(p.id)} className="text-xs text-red-600 hover:underline">Anular</button>}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
