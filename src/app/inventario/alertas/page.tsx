"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { ArrowLeft, Loader2, AlertTriangle } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Alerta = {
  id: string;
  nombre: string;
  sku: string | null;
  codigo_barras: string | null;
  stock_actual: number;
  stock_minimo: number;
  faltante: number;
  costo_promedio: number;
  precio_venta: number;
};

function fmt(n: number) {
  return (Number(n) || 0).toLocaleString("es-PY", { maximumFractionDigits: 3 });
}

export default function AlertasStockPage() {
  const [alertas, setAlertas] = useState<Alerta[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetchWithSupabaseSession("/api/inventario/alertas", { cache: "no-store" });
      const body = await res.json();
      if (!res.ok || body?.success === false) {
        setError(body?.error ?? "No se pudieron cargar las alertas.");
        return;
      }
      setAlertas((body.data.alertas ?? []) as Alerta[]);
    } catch {
      setError("Error de red.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  return (
    <div className="space-y-6 max-w-4xl">
      <Link href="/inventario" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a inventario
      </Link>

      <div className="flex items-center gap-3">
        <AlertTriangle className="h-7 w-7 text-amber-500" />
        <div>
          <h1 className="text-2xl font-bold text-gray-800">Alertas de stock mínimo</h1>
          <p className="text-sm text-gray-500">Productos en o por debajo de su stock mínimo configurado.</p>
        </div>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}

      <div className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden">
        {loading ? (
          <div className="p-6 flex items-center gap-2 text-sm text-gray-500"><Loader2 className="h-4 w-4 animate-spin" /> Cargando…</div>
        ) : alertas.length === 0 ? (
          <p className="text-sm text-emerald-700 p-6">✓ No hay productos por debajo del stock mínimo.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-sm">
              <thead className="bg-slate-50 text-xs uppercase text-gray-500">
                <tr>
                  <th className="py-3 px-4 text-left font-medium">Producto</th>
                  <th className="py-3 px-4 text-right font-medium">Stock actual</th>
                  <th className="py-3 px-4 text-right font-medium">Mínimo</th>
                  <th className="py-3 px-4 text-right font-medium">Faltante</th>
                  <th className="py-3 px-4 text-right font-medium">Historial</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {alertas.map((a) => (
                  <tr key={a.id} className="hover:bg-amber-50/40">
                    <td className="py-2.5 px-4 text-gray-800">
                      {a.nombre}
                      {a.sku ? <span className="text-gray-400 text-xs"> · {a.sku}</span> : null}
                    </td>
                    <td className="py-2.5 px-4 text-right tabular-nums font-medium text-red-600">{fmt(a.stock_actual)}</td>
                    <td className="py-2.5 px-4 text-right tabular-nums">{fmt(a.stock_minimo)}</td>
                    <td className="py-2.5 px-4 text-right tabular-nums font-semibold text-amber-600">{fmt(a.faltante)}</td>
                    <td className="py-2.5 px-4 text-right">
                      <Link href={`/inventario/productos/${a.id}/historial`} className="text-xs font-semibold text-[#17191C] hover:underline">Ver</Link>
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
