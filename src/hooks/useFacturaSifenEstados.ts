import { useEffect, useState } from "react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";

/** Respuesta alineada a POST /api/facturas/sifen/estados */
export type FacturaSifenEstadoItem = {
  factura_electronica_id: string | null;
  estado_sifen: string | null;
};

export type FacturaSifenEstadoMap = Record<string, FacturaSifenEstadoItem>;

export type FacturaSifenEstadosState = {
  estados: FacturaSifenEstadoMap;
  /** true mientras la petición en lote no terminó. Distingue "cargando" de
   *  "ya cargó y no hay DE" (que llega como estados con estado_sifen=null). */
  loading: boolean;
};

/**
 * Carga en lote el estado SIFEN para un conjunto de facturas (una sola petición),
 * exponiendo además el flag `loading`.
 * `estado_sifen === null` → sin registro en factura_electronica (UI: "Sin SIFEN").
 */
export function useFacturaSifenEstadosState(facturaIds: readonly string[]): FacturaSifenEstadosState {
  const sortedKey = [...new Set(facturaIds.filter(Boolean))].sort().join("|");
  // loading arranca en true: hasta que la primera carga resuelve no se toman
  // decisiones (evita ocultar/mostrar de más en el primer render).
  const [state, setState] = useState<FacturaSifenEstadosState>({ estados: {}, loading: true });

  useEffect(() => {
    if (!sortedKey) {
      setState({ estados: {}, loading: false });
      return;
    }
    const ids = sortedKey.split("|");
    let cancelled = false;
    setState((s) => ({ estados: s.estados, loading: true }));
    (async () => {
      try {
        const res = await fetchWithSupabaseSession("/api/facturas/sifen/estados", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ factura_ids: ids }),
        });
        const j = (await res.json()) as {
          success?: boolean;
          data?: { by_factura_id?: FacturaSifenEstadoMap };
        };
        if (cancelled) return;
        if (!j.success) {
          setState({ estados: {}, loading: false });
          return;
        }
        setState({ estados: j.data?.by_factura_id ?? {}, loading: false });
      } catch {
        if (!cancelled) setState({ estados: {}, loading: false });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [sortedKey]);

  return state;
}

/**
 * Compat: devuelve solo el mapa de estados (sin flag de carga). Usado por vistas
 * que solo muestran el badge por fila.
 */
export function useFacturaSifenEstados(facturaIds: readonly string[]): FacturaSifenEstadoMap {
  return useFacturaSifenEstadosState(facturaIds).estados;
}
