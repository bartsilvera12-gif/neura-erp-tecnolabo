"use client";

import Link from "next/link";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useState } from "react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";
import { FacturaElectronicaPanel } from "@/components/sifen/FacturaElectronicaPanel";
import type { FacturaElectronicaDTO, SifenCancelacionPreviewDTO } from "@/lib/sifen/types";

type FacturaApiRow = {
  id: string;
  numero_factura: string;
  fecha: string;
  fecha_vencimiento: string;
  monto: number;
  saldo: number;
  estado: string;
  tipo: string;
  moneda: string;
  cliente_id: string;
  cliente_display?: string;
  presupuesto_id?: string | null;
  estado_entrega?: string | null;
  numero_orden_compra?: string | null;
};

const ENTREGA_LABEL: Record<string, string> = { pendiente: "Entrega pendiente", parcialmente_entregada: "Entrega parcial", entregada: "Entregada" };
const ENTREGA_BADGE: Record<string, string> = { pendiente: "bg-slate-100 text-slate-600", parcialmente_entregada: "bg-amber-100 text-amber-700", entregada: "bg-emerald-100 text-emerald-700" };

type SifenResumen = {
  sifen_config_exists: boolean;
  sifen_config_activa: boolean;
  sifen_ambiente: string | null;
  sifen_plazo_cancelacion_horas: number;
  factura_electronica: FacturaElectronicaDTO | null;
  cancelacion: SifenCancelacionPreviewDTO | null;
};

function formatFecha(str: string) {
  if (!str) return "—";
  const [y, m, d] = str.split("-");
  return `${d}/${m}/${y}`;
}

function FacturaDetalleInner() {
  const params = useParams();
  const searchParams = useSearchParams();
  const id = params?.id as string | undefined;

  const [factura, setFactura] = useState<FacturaApiRow | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [resumen, setResumen] = useState<SifenResumen | null>(null);
  const [loadingF, setLoadingF] = useState(true);
  const [loadingS, setLoadingS] = useState(true);
  const [editandoOC, setEditandoOC] = useState(false);
  const [ocDraft, setOcDraft] = useState("");
  const [savingOC, setSavingOC] = useState(false);
  const [ocErr, setOcErr] = useState<string | null>(null);

  const onResumenLoaded = useCallback((r: SifenResumen) => {
    setResumen(r);
  }, []);

  const guardarOC = useCallback(async () => {
    if (!id) return;
    setSavingOC(true);
    setOcErr(null);
    try {
      const res = await fetchWithSupabaseSession(`/api/facturas/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ numero_orden_compra: ocDraft.trim() || null }),
      });
      const j = (await res.json()) as { success?: boolean; data?: { numero_orden_compra?: string | null }; error?: string };
      if (!res.ok || !j.success) {
        setOcErr(j.error ?? "No se pudo guardar.");
        return;
      }
      setFactura((prev) => (prev ? { ...prev, numero_orden_compra: j.data?.numero_orden_compra ?? null } : prev));
      setEditandoOC(false);
    } catch {
      setOcErr("No se pudo guardar.");
    } finally {
      setSavingOC(false);
    }
  }, [id, ocDraft]);

  const reloadFacturaComercial = useCallback(async () => {
    if (!id) return;
    try {
      const res = await fetchWithSupabaseSession(`/api/facturas/${id}`);
      const j = (await res.json()) as { success?: boolean; data?: FacturaApiRow; error?: string };
      if (res.ok && j.success && j.data) setFactura(j.data);
    } catch {
      /* ignorar */
    }
  }, [id]);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    (async () => {
      setLoadingF(true);
      setLoadErr(null);
      try {
        const res = await fetchWithSupabaseSession(`/api/facturas/${id}`);
        const j = (await res.json()) as { success?: boolean; data?: FacturaApiRow; error?: string };
        if (cancelled) return;
        if (res.status === 404) {
          setNotFound(true);
          setFactura(null);
          return;
        }
        if (!res.ok || !j.success || !j.data) {
          setLoadErr(j.error ?? "No se pudo cargar la factura");
          setFactura(null);
          return;
        }
        setNotFound(false);
        setFactura(j.data);
      } catch {
        if (!cancelled) setLoadErr("Error de red");
      } finally {
        if (!cancelled) setLoadingF(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    (async () => {
      setLoadingS(true);
      try {
        const res = await fetchWithSupabaseSession(`/api/facturas/${id}/sifen/resumen`);
        const j = (await res.json()) as { success?: boolean; data?: SifenResumen };
        if (cancelled) return;
        if (res.ok && j.success && j.data) setResumen(j.data);
        else setResumen(null);
      } catch {
        if (!cancelled) setResumen(null);
      } finally {
        if (!cancelled) setLoadingS(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  useEffect(() => {
    if (searchParams?.get("print") === "1" && factura && !loadingF) {
      const t = setTimeout(() => window.print(), 400);
      return () => clearTimeout(t);
    }
  }, [searchParams, factura, loadingF]);

  if (!id) {
    return null;
  }

  if (loadingF) {
    return (
      <div className="max-w-6xl mx-auto py-20 text-center text-sm text-slate-400">Cargando factura…</div>
    );
  }

  if (notFound) {
    return (
      <div className="max-w-6xl mx-auto py-20 text-center space-y-3">
        <p className="text-slate-600">Factura no encontrada.</p>
        <Link href="/gestion-clientes" className="text-[#1E2125] text-sm font-medium hover:underline">
          Volver a gestión de clientes
        </Link>
      </div>
    );
  }

  if (loadErr || !factura) {
    return (
      <div className="max-w-6xl mx-auto py-20 text-center space-y-3">
        <p className="text-red-600 text-sm">{loadErr ?? "Error"}</p>
        <Link href="/gestion-clientes" className="text-[#1E2125] text-sm font-medium hover:underline">
          Volver
        </Link>
      </div>
    );
  }

  const monedaLabel = factura.moneda === "USD" ? "USD" : "Gs.";

  return (
    <div className="max-w-6xl mx-auto space-y-6 py-6 px-4 sm:px-6 print:px-0 w-full">
      <div className="flex flex-wrap items-start justify-between gap-4 print:hidden">
        <div>
          <Link
            href={`/gestion-clientes?cliente=${encodeURIComponent(factura.cliente_id)}`}
            className="text-xs font-medium text-[#1E2125] hover:underline"
          >
            ← Gestión de clientes
          </Link>
          <h1 className="text-2xl font-bold text-slate-900 mt-1">Factura {factura.numero_factura}</h1>
          <p className="text-sm text-slate-500 mt-0.5">
            Cliente:{" "}
            <Link href={`/clientes/${factura.cliente_id}`} className="text-[#1E2125] font-medium hover:underline">
              {factura.cliente_display ?? "Ver cliente"}
            </Link>
          </p>
          {factura.presupuesto_id && (
            <p className="text-sm text-slate-500 mt-0.5">
              Origen:{" "}
              <Link href={`/presupuestos/${factura.presupuesto_id}`} className="text-[#1E2125] font-medium hover:underline">
                Ver presupuesto de origen
              </Link>
            </p>
          )}
        </div>
        <div className="flex items-center gap-2 print:hidden">
          {factura.estado_entrega && (
            <span className={`text-xs font-semibold px-2.5 py-1 rounded-full ${ENTREGA_BADGE[factura.estado_entrega] ?? "bg-slate-100 text-slate-600"}`}>
              {ENTREGA_LABEL[factura.estado_entrega] ?? factura.estado_entrega}
            </span>
          )}
          <Link
            href={`/facturas/${factura.id}/remisiones`}
            className="text-xs font-semibold px-3 py-2 rounded-lg bg-[#1E2125] text-white hover:bg-[#17191C]"
          >
            Remisiones / entregas
          </Link>
          <button
            type="button"
            onClick={() => window.print()}
            className="text-xs font-semibold px-3 py-2 rounded-lg border border-slate-200 text-slate-700 hover:bg-slate-50"
          >
            Imprimir
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-slate-200 bg-white shadow-sm p-5 space-y-3">
        <h2 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Resumen comercial</h2>
        <dl className="grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
          <div>
            <dt className="text-slate-400 text-xs">Emisión</dt>
            <dd className="font-medium text-slate-800">{formatFecha(factura.fecha)}</dd>
          </div>
          <div>
            <dt className="text-slate-400 text-xs">Vencimiento</dt>
            <dd className="font-medium text-slate-800">{formatFecha(factura.fecha_vencimiento)}</dd>
          </div>
          <div>
            <dt className="text-slate-400 text-xs">Tipo</dt>
            <dd className="font-medium text-slate-800 capitalize">{factura.tipo}</dd>
          </div>
          <div>
            <dt className="text-slate-400 text-xs">N.º Orden de Compra</dt>
            {editandoOC ? (
              <dd className="mt-0.5">
                <div className="flex flex-wrap items-center gap-1.5">
                  <input
                    type="text"
                    value={ocDraft}
                    onChange={(e) => setOcDraft(e.target.value)}
                    maxLength={60}
                    autoFocus
                    placeholder="OC-25874"
                    onKeyDown={(e) => {
                      if (e.key === "Enter") guardarOC();
                      if (e.key === "Escape") setEditandoOC(false);
                    }}
                    className="w-40 rounded border border-slate-300 px-2 py-1 text-sm text-slate-800 focus:border-slate-500 focus:outline-none"
                  />
                  <button
                    type="button"
                    onClick={guardarOC}
                    disabled={savingOC}
                    className="rounded bg-slate-800 px-2 py-1 text-xs font-medium text-white hover:bg-slate-700 disabled:opacity-50"
                  >
                    {savingOC ? "Guardando…" : "Guardar"}
                  </button>
                  <button
                    type="button"
                    onClick={() => setEditandoOC(false)}
                    disabled={savingOC}
                    className="rounded px-2 py-1 text-xs font-medium text-slate-500 hover:text-slate-700"
                  >
                    Cancelar
                  </button>
                </div>
                {ocErr ? <p className="mt-1 text-xs text-red-600">{ocErr}</p> : null}
              </dd>
            ) : (
              <dd className="flex items-center gap-2">
                <span className="font-medium text-slate-800">{factura.numero_orden_compra || "—"}</span>
                <button
                  type="button"
                  onClick={() => {
                    setOcDraft(factura.numero_orden_compra ?? "");
                    setOcErr(null);
                    setEditandoOC(true);
                  }}
                  className="text-xs font-medium text-slate-500 underline hover:text-slate-700"
                >
                  {factura.numero_orden_compra ? "Editar" : "Agregar"}
                </button>
              </dd>
            )}
          </div>
          <div>
            <dt className="text-slate-400 text-xs">Monto</dt>
            <dd className="font-semibold text-slate-900 tabular-nums">
              {monedaLabel}{" "}
              {factura.monto.toLocaleString(factura.moneda === "USD" ? "en-US" : "es-PY")}
            </dd>
          </div>
          <div>
            <dt className="text-slate-400 text-xs">Saldo</dt>
            <dd className="font-semibold text-slate-900 tabular-nums">
              {monedaLabel}{" "}
              {factura.saldo.toLocaleString(factura.moneda === "USD" ? "en-US" : "es-PY")}
            </dd>
          </div>
          <div>
            <dt className="text-slate-400 text-xs">Estado</dt>
            <dd className="font-medium text-slate-800">{factura.estado}</dd>
          </div>
        </dl>
      </div>

      {/*
        La OC viaja al KuDE dentro del XML (gOpeDE/dInfoEmi). Una vez firmado el
        DE, el KuDE se dibuja desde ese XML: cargarla despues ya no la hace
        aparecer en el impreso. Por eso el aviso va ANTES de emitir.
      */}
      {!factura.numero_orden_compra && (
        <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
          Esta factura no tiene N.º de Orden de Compra. Si el cliente la necesita impresa, cargala arriba ANTES de generar el documento electrónico: el KuDE se dibuja desde el XML firmado, así que agregarla después no la muestra en el impreso.
        </div>
      )}

      <FacturaElectronicaPanel
        facturaId={id}
        clienteId={factura.cliente_id}
        facturaComercial={{
          monto: factura.monto,
          saldo: factura.saldo,
          estado: factura.estado,
          moneda: factura.moneda,
          cliente_display: factura.cliente_display ?? "",
        }}
        resumen={resumen}
        loadingResumen={loadingS}
        onResumenLoaded={onResumenLoaded}
        onComercialUpdated={reloadFacturaComercial}
      />
    </div>
  );
}

export default function FacturaDetallePage() {
  return (
    <Suspense
      fallback={
        <div className="max-w-6xl mx-auto py-20 text-center text-sm text-slate-400">Cargando factura…</div>
      }
    >
      <FacturaDetalleInner />
    </Suspense>
  );
}
