"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, Wallet } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

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
  const [filtroEstado, setFiltroEstado] = useState("");

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
