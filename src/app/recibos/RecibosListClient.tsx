"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Filter, Loader2, Printer, Receipt } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

type Row = {
  id: string;
  numero_recibo: string;
  fecha: string;
  cliente_id: string | null;
  cliente_nombre: string | null;
  cliente_documento: string | null;
  origen: string;
  moneda: string;
  monto: number;
  metodo_pago: string | null;
  referencia: string | null;
  concepto: string | null;
  usuario_nombre: string | null;
  anulado: boolean;
  venta_numero: string | null;
  factura_numero: string | null;
};

type ClienteOpt = { id: string; nombre: string };

const ORIGENES = [
  { v: "", l: "Todos los orígenes" },
  { v: "cobro_cxc", l: "Cobro a crédito" },
  { v: "venta_contado", l: "Venta contado" },
];

const ORIGEN_LABEL: Record<string, string> = {
  cobro_cxc: "Cobro a crédito",
  venta_contado: "Venta contado",
};

const METODOS = [
  { v: "", l: "Todos los métodos" },
  { v: "efectivo", l: "Efectivo" },
  { v: "transferencia", l: "Transferencia" },
  { v: "tarjeta", l: "Tarjeta" },
  { v: "cheque", l: "Cheque" },
];

function fmtFecha(v: string): string {
  try {
    return new Date(v).toLocaleDateString("es-PY");
  } catch {
    return v;
  }
}

function fmtMonto(n: number, moneda: string): string {
  const s = Math.round(Number(n) || 0).toLocaleString("es-PY");
  return moneda === "USD" ? `US$ ${s}` : `Gs. ${s}`;
}

export default function RecibosListClient() {
  const [rows, setRows] = useState<Row[]>([]);
  const [total, setTotal] = useState(0);
  const [suma, setSuma] = useState(0);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [clientes, setClientes] = useState<ClienteOpt[]>([]);

  const VACIO = { desde: "", hasta: "", cliente_id: "", origen: "", metodo_pago: "", q: "" };
  const [form, setForm] = useState(VACIO);
  const [aplicados, setAplicados] = useState(VACIO);

  const cargar = useCallback(async () => {
    setCargando(true);
    setError(null);
    try {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(aplicados)) if (v) qs.set(k, v);
      const res = await fetchWithSupabaseSession(`/api/recibos-dinero?${qs.toString()}`, { cache: "no-store" });
      const j = await res.json();
      if (!res.ok || !j.success) throw new Error(j.error ?? "No se pudo cargar.");
      setRows((j.data.rows ?? []) as Row[]);
      setTotal(Number(j.data.total) || 0);
      setSuma(Number(j.data.sumaVigente) || 0);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error al cargar.");
    } finally {
      setCargando(false);
    }
  }, [aplicados]);

  useEffect(() => {
    void cargar();
  }, [cargar]);

  useEffect(() => {
    (async () => {
      try {
        const res = await fetchWithSupabaseSession("/api/clientes?limit=500", { cache: "no-store" });
        const j = await res.json();
        const arr = (j?.data?.clientes ?? j?.data ?? []) as Array<Record<string, unknown>>;
        if (Array.isArray(arr)) {
          setClientes(
            arr
              .map((c) => ({
                id: String(c.id ?? ""),
                nombre: String(c.empresa || c.nombre_contacto || c.nombre || "").trim(),
              }))
              .filter((c) => c.id && c.nombre),
          );
        }
      } catch {
        /* el filtro de cliente queda vacío, no es bloqueante */
      }
    })();
  }, []);

  const inputCls =
    "w-full rounded-md border border-slate-300 bg-white px-3 py-2 text-sm text-slate-800 focus:border-slate-400 focus:outline-none";
  const labelCls = "mb-1 block text-[11px] font-semibold uppercase tracking-wide text-slate-500";

  return (
    <div className="space-y-5 p-4 sm:p-6">
      <div>
        <p className="text-[11px] font-semibold uppercase tracking-wider text-amber-700">● Auditoría</p>
        <h1 className="text-2xl font-bold text-slate-800">Recibos de dinero</h1>
        <p className="text-sm text-slate-500">
          Todos los recibos emitidos al cobrar. Vínculo al cliente, a la factura cobrada y al usuario que lo generó.
        </p>
      </div>

      {/* Filtros */}
      <div className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <p className="mb-4 border-l-4 border-amber-600 pl-2 text-[11px] font-bold uppercase tracking-wider text-slate-600">
          Filtros
        </p>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-6">
          <div>
            <label className={labelCls}>Desde</label>
            <input type="date" value={form.desde} onChange={(e) => setForm((p) => ({ ...p, desde: e.target.value }))} className={inputCls} />
          </div>
          <div>
            <label className={labelCls}>Hasta</label>
            <input type="date" value={form.hasta} onChange={(e) => setForm((p) => ({ ...p, hasta: e.target.value }))} className={inputCls} />
          </div>
          <div>
            <label className={labelCls}>Cliente</label>
            <select value={form.cliente_id} onChange={(e) => setForm((p) => ({ ...p, cliente_id: e.target.value }))} className={inputCls}>
              <option value="">Todos los clientes</option>
              {clientes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelCls}>Origen</label>
            <select value={form.origen} onChange={(e) => setForm((p) => ({ ...p, origen: e.target.value }))} className={inputCls}>
              {ORIGENES.map((o) => (
                <option key={o.v} value={o.v}>
                  {o.l}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelCls}>Método de pago</label>
            <select value={form.metodo_pago} onChange={(e) => setForm((p) => ({ ...p, metodo_pago: e.target.value }))} className={inputCls}>
              {METODOS.map((m) => (
                <option key={m.v} value={m.v}>
                  {m.l}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className={labelCls}>Buscar</label>
            <input
              value={form.q}
              onChange={(e) => setForm((p) => ({ ...p, q: e.target.value }))}
              onKeyDown={(e) => {
                if (e.key === "Enter") setAplicados({ ...form });
              }}
              placeholder="N.º recibo, cliente, concepto o referencia"
              className={inputCls}
            />
          </div>
        </div>

        <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setAplicados({ ...form })}
              className="inline-flex items-center gap-2 rounded-md bg-amber-700 px-4 py-2 text-sm font-medium text-white hover:bg-amber-800"
            >
              <Filter className="h-4 w-4" /> Aplicar filtros
            </button>
            <button
              type="button"
              onClick={() => {
                setForm(VACIO);
                setAplicados(VACIO);
              }}
              className="rounded-md border border-slate-300 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50"
            >
              Limpiar
            </button>
          </div>
          <p className="text-sm text-slate-500">
            <span className="font-semibold text-slate-700">{total}</span> recibos
            {/* La suma ignora los anulados: es el dinero efectivamente recibido. */}
            {rows.length > 0 && <> · cobrado {fmtMonto(suma, rows[0]!.moneda)}</>}
          </p>
        </div>
      </div>

      {error && <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700">{error}</div>}

      {/* Tabla */}
      <div className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1040px] text-sm">
            <thead>
              <tr className="border-b border-slate-200 bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500">
                <th className="px-4 py-3 text-left">Fecha</th>
                <th className="px-4 py-3 text-left">N.º recibo</th>
                <th className="px-4 py-3 text-left">Cliente</th>
                <th className="px-4 py-3 text-left">Origen</th>
                <th className="px-4 py-3 text-left">Documento</th>
                <th className="px-4 py-3 text-left">Método</th>
                <th className="px-4 py-3 text-right">Monto</th>
                <th className="px-4 py-3 text-left">Usuario</th>
                <th className="px-4 py-3 text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              {cargando ? (
                <tr>
                  <td colSpan={9} className="px-4 py-10 text-center text-slate-400">
                    <Loader2 className="mx-auto h-5 w-5 animate-spin" />
                  </td>
                </tr>
              ) : rows.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-4 py-10 text-center text-sm text-slate-500">
                    <Receipt className="mx-auto mb-2 h-6 w-6 text-slate-300" />
                    No hay recibos con estos filtros.
                    <br />
                    <span className="text-xs text-slate-400">
                      Se generan al registrar un cobro desde <Link href="/pagos" className="underline">Pagos</Link> o
                      el estado de cuenta del cliente.
                    </span>
                  </td>
                </tr>
              ) : (
                rows.map((r) => (
                  <tr key={r.id} className={`border-b border-slate-100 hover:bg-slate-50/60 ${r.anulado ? "opacity-60" : ""}`}>
                    <td className="px-4 py-3 text-slate-600">{fmtFecha(r.fecha)}</td>
                    <td className="px-4 py-3 font-mono font-medium text-slate-800">
                      {r.numero_recibo}
                      {r.anulado && (
                        <span className="ml-2 rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-semibold text-red-700">
                          Anulado
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-slate-700">
                      {r.cliente_id ? (
                        <Link href={`/clientes/${r.cliente_id}`} className="hover:underline">
                          {r.cliente_nombre ?? "—"}
                        </Link>
                      ) : (
                        (r.cliente_nombre ?? "—")
                      )}
                      {r.cliente_documento && <span className="block text-[11px] text-slate-400">{r.cliente_documento}</span>}
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                          r.origen === "cobro_cxc" ? "bg-emerald-100 text-emerald-800" : "bg-slate-100 text-slate-600"
                        }`}
                      >
                        {ORIGEN_LABEL[r.origen] ?? r.origen}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-slate-600">{r.factura_numero ?? r.venta_numero ?? "—"}</td>
                    <td className="px-4 py-3 text-slate-600">
                      {r.metodo_pago ?? "—"}
                      {r.referencia && <span className="block text-[11px] text-slate-400">{r.referencia}</span>}
                    </td>
                    <td className="px-4 py-3 text-right font-semibold tabular-nums text-slate-800">
                      {fmtMonto(r.monto, r.moneda)}
                    </td>
                    <td className="px-4 py-3 text-slate-500">{r.usuario_nombre ?? "—"}</td>
                    <td className="px-4 py-3">
                      <div className="flex justify-end">
                        <a
                          href={`/api/recibos-dinero/${r.id}/pdf?auto=1`}
                          target="_blank"
                          rel="noopener"
                          title="Imprimir recibo"
                          className="rounded p-1.5 text-slate-500 hover:bg-slate-100"
                        >
                          <Printer className="h-4 w-4" />
                        </a>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
