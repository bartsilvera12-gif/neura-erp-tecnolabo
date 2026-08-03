"use client";

import { useCallback, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { ArrowLeft, Loader2, TrendingUp } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Historial = {
  producto: {
    id: string; nombre: string; sku: string | null;
    stock_actual: number; costo_promedio: number; precio_venta: number;
    precio_mayorista: number | null; margen_pct: number | null;
  };
  movimientos: Array<{ id: string; tipo: string; cantidad: number; origen: string; referencia: string | null; fecha: string; usuario_nombre: string | null; observacion: string | null }>;
  compras: Array<{ fecha: string; proveedor_nombre: string | null; cantidad: number; costo_unitario: number; moneda: string; numero_control: string }>;
  evolucion_costos: Array<{ fecha: string; costo_unitario: number }>;
};

const fmtG = (n: number) => "Gs. " + (Number(n) || 0).toLocaleString("es-PY", { maximumFractionDigits: 0 });
const fmtN = (n: number) => (Number(n) || 0).toLocaleString("es-PY", { maximumFractionDigits: 3 });
const fmtF = (iso: string) => { try { return new Date(iso).toLocaleDateString("es-PY"); } catch { return iso; } };

const TIPO_COLOR: Record<string, string> = { ENTRADA: "text-emerald-600", SALIDA: "text-red-600", AJUSTE: "text-amber-600" };

function Sparkline({ data }: { data: number[] }) {
  if (data.length < 2) return null;
  const w = 260, h = 48, min = Math.min(...data), max = Math.max(...data);
  const rango = max - min || 1;
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * w},${h - ((v - min) / rango) * (h - 8) - 4}`).join(" ");
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full max-w-[260px] h-12">
      <polyline points={pts} fill="none" stroke="#4FAEB2" strokeWidth="2" />
    </svg>
  );
}

export default function HistorialProductoPage() {
  const params = useParams<{ id: string }>();
  const id = params.id;
  const [h, setH] = useState<Historial | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchWithSupabaseSession(`/api/inventario/productos/${id}/historial`, { cache: "no-store" });
      const body = await res.json();
      if (!res.ok || body?.success === false) {
        setError(body?.error ?? "No se pudo cargar el historial.");
        return;
      }
      setH(body.data as Historial);
    } catch {
      setError("Error de red.");
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => { void cargar(); }, [cargar]);

  if (loading) return <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>;
  if (!h) return <div className="p-6 space-y-3"><div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error ?? "No encontrado"}</div><Link href="/inventario" className="text-sm text-[#4FAEB2] hover:underline">Volver</Link></div>;

  const p = h.producto;
  return (
    <div className="space-y-6 max-w-5xl">
      <Link href="/inventario" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a inventario
      </Link>

      <div>
        <h1 className="text-2xl font-bold text-gray-800">{p.nombre}</h1>
        {p.sku && <p className="text-sm text-gray-500">SKU: {p.sku}</p>}
      </div>

      {/* Resumen costo / precio / margen */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {[
          { l: "Stock actual", v: fmtN(p.stock_actual) },
          { l: "Costo prom.", v: fmtG(p.costo_promedio) },
          { l: "Precio venta", v: fmtG(p.precio_venta) },
          { l: "P. mayorista", v: p.precio_mayorista != null ? fmtG(p.precio_mayorista) : "—" },
          { l: "Margen", v: p.margen_pct != null ? `${p.margen_pct}%` : "—" },
        ].map((c) => (
          <div key={c.l} className="bg-white rounded-xl border border-slate-200 shadow-sm p-4">
            <div className="text-xs uppercase tracking-wide text-gray-500">{c.l}</div>
            <div className="mt-1 text-lg font-semibold text-gray-800 tabular-nums">{c.v}</div>
          </div>
        ))}
      </div>

      {/* Evolución de costos */}
      {h.evolucion_costos.length >= 2 && (
        <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
          <h2 className="text-sm font-semibold text-gray-700 mb-2 flex items-center gap-1.5"><TrendingUp className="h-4 w-4 text-[#4FAEB2]" /> Evolución de costos</h2>
          <Sparkline data={h.evolucion_costos.map((e) => e.costo_unitario)} />
          <div className="mt-1 flex justify-between text-xs text-gray-500">
            <span>{fmtF(h.evolucion_costos[0].fecha)} · {fmtG(h.evolucion_costos[0].costo_unitario)}</span>
            <span>{fmtF(h.evolucion_costos[h.evolucion_costos.length - 1].fecha)} · {fmtG(h.evolucion_costos[h.evolucion_costos.length - 1].costo_unitario)}</span>
          </div>
        </div>
      )}

      {/* Compras por proveedor */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <h2 className="text-sm font-semibold text-gray-700 p-5 pb-2">Historial de compras</h2>
        {h.compras.length === 0 ? (
          <p className="text-sm text-gray-500 px-5 pb-5">Sin compras registradas.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[560px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-gray-500">
                <tr><th className="py-2.5 px-4 text-left font-medium">Fecha</th><th className="py-2.5 px-4 text-left font-medium">Proveedor</th><th className="py-2.5 px-4 text-right font-medium">Cantidad</th><th className="py-2.5 px-4 text-right font-medium">Costo unit.</th><th className="py-2.5 px-4 text-left font-medium">Compra</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {h.compras.map((c, i) => (
                  <tr key={i}>
                    <td className="py-2 px-4 text-gray-600">{fmtF(c.fecha)}</td>
                    <td className="py-2 px-4 text-gray-800">{c.proveedor_nombre ?? "—"}</td>
                    <td className="py-2 px-4 text-right tabular-nums">{fmtN(c.cantidad)}</td>
                    <td className="py-2 px-4 text-right tabular-nums">{fmtG(c.costo_unitario)}</td>
                    <td className="py-2 px-4"><Link href={`/compras/${encodeURIComponent(c.numero_control)}/recepciones`} className="text-[#3F8E91] hover:underline">{c.numero_control}</Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Movimientos */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        <h2 className="text-sm font-semibold text-gray-700 p-5 pb-2">Movimientos de inventario</h2>
        {h.movimientos.length === 0 ? (
          <p className="text-sm text-gray-500 px-5 pb-5">Sin movimientos.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-gray-500">
                <tr><th className="py-2.5 px-4 text-left font-medium">Fecha</th><th className="py-2.5 px-4 text-left font-medium">Tipo</th><th className="py-2.5 px-4 text-right font-medium">Cantidad</th><th className="py-2.5 px-4 text-left font-medium">Origen</th><th className="py-2.5 px-4 text-left font-medium">Documento</th><th className="py-2.5 px-4 text-left font-medium">Usuario</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {h.movimientos.map((m) => (
                  <tr key={m.id}>
                    <td className="py-2 px-4 text-gray-600">{fmtF(m.fecha)}</td>
                    <td className={`py-2 px-4 font-medium ${TIPO_COLOR[m.tipo] ?? ""}`}>{m.tipo}</td>
                    <td className="py-2 px-4 text-right tabular-nums">{fmtN(m.cantidad)}</td>
                    <td className="py-2 px-4 text-gray-600">{m.origen}</td>
                    <td className="py-2 px-4 text-gray-600">{m.referencia ?? "—"}</td>
                    <td className="py-2 px-4 text-gray-600">{m.usuario_nombre ?? "—"}</td>
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
