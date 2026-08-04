"use client";

import { Fragment, useEffect, useMemo, useState } from "react";
import { IVA_POR_DEFECTO } from "@/lib/branding/cliente";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { FileText, ArrowLeft, Plus, Trash2, Loader2, Image as ImageIcon, ChevronDown } from "lucide-react";
import { fetchWithSupabaseSession } from "@/lib/api/fetch-with-supabase-session";
import SelectFromList from "@/components/inventario/SelectFromList";
import ClienteBuscador, { type ClienteBuscadorItem } from "@/components/clientes/ClienteBuscador";
import { calcMontoIvaIncluido, type IvaTipoPresupuesto } from "@/lib/presupuestos/types";

type ProductoLite = {
  id: string;
  nombre: string;
  sku: string;
  precio_venta: number;
  unidad_medida: string;
};
type ClienteLite = {
  id: string;
  nombre: string;
  ruc: string | null;
  telefono: string | null;
  direccion: string | null;
};
type Item = {
  producto_id: string | null;
  producto_nombre: string;
  sku: string | null;
  cantidad: number;
  unidad_medida: string | null;
  precio_unitario: number;
  iva_tipo: IvaTipoPresupuesto;
  descuento: number;
  // Presentación comercial (Fase 1): visible en el presupuesto, NO en la factura.
  imagen_url: string | null;
  descripcion_comercial: string | null;
  especificaciones_tecnicas: string | null;
  /** Texto libre: una "clave: valor" por línea → se convierte en array. */
  caracteristicas_texto: string | null;
};

/** Convierte el textarea de características ("clave: valor" por línea) a array jsonb. */
function parseCaracteristicas(texto: string | null): Array<{ label: string; valor: string }> {
  if (!texto) return [];
  return texto
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => {
      const idx = l.indexOf(":");
      if (idx === -1) return { label: "", valor: l };
      return { label: l.slice(0, idx).trim(), valor: l.slice(idx + 1).trim() };
    });
}

function fmtGs(n: number) {
  return "Gs. " + (Number(n) || 0).toLocaleString("es-PY", { maximumFractionDigits: 0 });
}
function round2(n: number) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}
function itemTotals(it: Item) {
  const bruto = (Number(it.precio_unitario) || 0) * (Number(it.cantidad) || 0);
  const total = Math.max(0, bruto - (Number(it.descuento) || 0));
  const iva = round2(calcMontoIvaIncluido(it.iva_tipo, total));
  return { total: round2(total), iva, subtotal: round2(total - iva) };
}

const IVAS: IvaTipoPresupuesto[] = ["10%", "5%", "EXENTA"];
const labelClass = "block text-xs font-medium text-gray-600 mb-1";
const inputClass = "w-full rounded-md border border-gray-300 px-3 py-2 text-sm";

export default function NuevoPresupuestoPage() {
  const router = useRouter();
  const [productos, setProductos] = useState<ProductoLite[]>([]);
  const [clientes, setClientes] = useState<ClienteLite[]>([]);

  // Cliente
  const [clienteId, setClienteId] = useState("");
  const [clienteNombre, setClienteNombre] = useState("");
  const [clienteRuc, setClienteRuc] = useState("");
  const [clienteTel, setClienteTel] = useState("");
  const [clienteDir, setClienteDir] = useState("");

  // Items
  const [items, setItems] = useState<Item[]>([]);
  const [selProd, setSelProd] = useState("");

  // Condiciones
  const [validezDias, setValidezDias] = useState("15");
  const [formaPago, setFormaPago] = useState("");
  const [plazoEntrega, setPlazoEntrega] = useState("");
  const [observaciones, setObservaciones] = useState("");
  const [moneda, setMoneda] = useState<"PYG" | "USD">("PYG");
  const [tipoCambio, setTipoCambio] = useState("1");
  const [condiciones, setCondiciones] = useState("");
  const [expandido, setExpandido] = useState<Record<number, boolean>>({});

  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchWithSupabaseSession("/api/productos", { cache: "no-store" })
      .then((r) => r.json())
      .then((j) => {
        if (j?.success) {
          const list = (j.data?.productos ?? []) as Record<string, unknown>[];
          setProductos(
            list
              .filter((p) => p.es_vendible !== false)
              .map((p) => ({
                id: String(p.id),
                nombre: String(p.nombre),
                sku: String(p.sku ?? ""),
                precio_venta: Number(p.precio_venta) || 0,
                unidad_medida: String(p.unidad_medida ?? "UNIDAD"),
              }))
          );
        }
      })
      .catch(() => {});
    fetchWithSupabaseSession("/api/clientes", { cache: "no-store" })
      .then((r) => r.json())
      .then((j) => {
        if (j?.success && Array.isArray(j.data)) {
          const s = (v: unknown) => (typeof v === "string" ? v.trim() : "");
          setClientes(
            (j.data as Record<string, unknown>[]).map((r) => ({
              id: String(r.id),
              nombre: s(r.empresa) || s(r.nombre_contacto) || s(r.nombre) || "Cliente",
              ruc: s(r.ruc) || null,
              telefono: s(r.telefono) || null,
              direccion: s(r.direccion) || null,
            }))
          );
        }
      })
      .catch(() => {});
  }, []);

  function seleccionarCliente(id: string) {
    setClienteId(id);
    const c = clientes.find((x) => x.id === id);
    if (c) {
      setClienteNombre(c.nombre);
      setClienteRuc(c.ruc ?? "");
      setClienteTel(c.telefono ?? "");
      setClienteDir(c.direccion ?? "");
    }
  }

  function agregarProducto() {
    const p = productos.find((x) => x.id === selProd);
    if (!p) return;
    if (items.some((it) => it.producto_id === p.id)) return;
    setItems((prev) => [
      ...prev,
      {
        producto_id: p.id,
        producto_nombre: p.nombre,
        sku: p.sku || null,
        cantidad: 1,
        unidad_medida: p.unidad_medida,
        precio_unitario: p.precio_venta,
        iva_tipo: IVA_POR_DEFECTO,
        descuento: 0,
        imagen_url: null,
        descripcion_comercial: null,
        especificaciones_tecnicas: null,
        caracteristicas_texto: null,
      },
    ]);
    setSelProd("");
  }

  function agregarManual() {
    setItems((prev) => [
      ...prev,
      {
        producto_id: null,
        producto_nombre: "",
        sku: null,
        cantidad: 1,
        unidad_medida: null,
        precio_unitario: 0,
        iva_tipo: IVA_POR_DEFECTO,
        descuento: 0,
        imagen_url: null,
        descripcion_comercial: null,
        especificaciones_tecnicas: null,
        caracteristicas_texto: null,
      },
    ]);
  }

  function updItem(i: number, patch: Partial<Item>) {
    setItems((prev) => prev.map((it, idx) => (idx === i ? { ...it, ...patch } : it)));
  }
  function delItem(i: number) {
    setItems((prev) => prev.filter((_, idx) => idx !== i));
  }

  const totales = useMemo(() => {
    let subtotal = 0,
      iva = 0,
      desc = 0,
      total = 0;
    for (const it of items) {
      const t = itemTotals(it);
      subtotal += t.subtotal;
      iva += t.iva;
      total += t.total;
      desc += Number(it.descuento) || 0;
    }
    return { subtotal: round2(subtotal), iva: round2(iva), desc: round2(desc), total: round2(total) };
  }, [items]);

  const valido =
    clienteNombre.trim().length > 0 &&
    items.length > 0 &&
    items.every((it) => it.producto_nombre.trim() && it.cantidad > 0 && it.precio_unitario >= 0);

  async function guardar() {
    if (guardando || !valido) return;
    setGuardando(true);
    setError(null);
    try {
      const res = await fetchWithSupabaseSession("/api/presupuestos", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          cliente_id: clienteId || null,
          cliente_nombre: clienteNombre.trim(),
          cliente_ruc: clienteRuc.trim() || null,
          cliente_telefono: clienteTel.trim() || null,
          cliente_direccion: clienteDir.trim() || null,
          moneda,
          tipo_cambio: moneda === "USD" ? Number(tipoCambio) || 1 : 1,
          validez_dias: validezDias.trim() === "" ? null : parseInt(validezDias, 10),
          forma_pago: formaPago.trim() || null,
          plazo_entrega: plazoEntrega.trim() || null,
          condiciones_comerciales: condiciones.trim() || null,
          observaciones: observaciones.trim() || null,
          items: items.map((it) => ({
            producto_id: it.producto_id,
            producto_nombre: it.producto_nombre.trim(),
            sku: it.sku,
            cantidad: Number(it.cantidad),
            unidad_medida: it.unidad_medida,
            precio_unitario: Number(it.precio_unitario),
            iva_tipo: it.iva_tipo,
            descuento: Number(it.descuento) || 0,
            imagen_url: it.imagen_url?.trim() || null,
            descripcion_comercial: it.descripcion_comercial?.trim() || null,
            especificaciones_tecnicas: it.especificaciones_tecnicas?.trim() || null,
            caracteristicas: parseCaracteristicas(it.caracteristicas_texto),
          })),
        }),
      });
      const body = await res.json();
      if (!res.ok || body?.success === false) {
        setError(body?.error ?? "No se pudo guardar el presupuesto.");
        return;
      }
      router.push(`/presupuestos/${body.data.id}`);
    } catch {
      setError("Error de red al guardar el presupuesto.");
    } finally {
      setGuardando(false);
    }
  }

  return (
    <div className="space-y-6">
      <Link href="/presupuestos" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Volver a presupuestos
      </Link>

      <div className="flex items-center gap-3">
        <FileText className="h-7 w-7 text-[#4FAEB2]" />
        <h1 className="text-2xl sm:text-3xl font-bold text-gray-800">Nuevo presupuesto</h1>
      </div>

      {error && <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">{error}</div>}

      {/* Cliente */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-3">Cliente</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="sm:col-span-2">
            <ClienteBuscador
              clientes={clientes as ClienteBuscadorItem[]}
              value={clienteId}
              onSelect={(c) => {
                setClienteId(c.id);
                setClienteNombre(c.nombre);
                setClienteRuc(c.ruc ?? "");
                setClienteTel(c.telefono ?? "");
                setClienteDir(c.direccion ?? "");
              }}
              onClear={() => {
                setClienteId("");
              }}
              label="Cliente existente (opcional)"
            />
            <p className="mt-1 text-[11px] text-gray-400">O completá los campos de abajo manualmente si es un cliente nuevo.</p>
          </div>
          <div>
            <label className={labelClass}>Nombre / Razón social *</label>
            <input value={clienteNombre} onChange={(e) => { setClienteId(""); setClienteNombre(e.target.value); }} className={inputClass} placeholder="Nombre del cliente" />
          </div>
          <div>
            <label className={labelClass}>RUC / CI</label>
            <input value={clienteRuc} onChange={(e) => setClienteRuc(e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>Teléfono</label>
            <input value={clienteTel} onChange={(e) => setClienteTel(e.target.value)} className={inputClass} />
          </div>
          <div className="sm:col-span-2">
            <label className={labelClass}>Dirección</label>
            <input value={clienteDir} onChange={(e) => setClienteDir(e.target.value)} className={inputClass} />
          </div>
        </div>
      </div>

      {/* Productos */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-3">Productos</h2>
        <div className="flex flex-wrap items-end gap-2 mb-4">
          <div className="flex-1 min-w-[260px]">
            <label className={labelClass}>Agregar desde inventario</label>
            <SelectFromList
              value={selProd || null}
              onChange={(v) => setSelProd(v ?? "")}
              placeholder="— Buscá un producto por nombre o SKU —"
              options={productos
                .filter((p) => !items.some((it) => it.producto_id === p.id))
                .map((p) => ({ id: p.id, label: p.nombre, sublabel: p.sku || undefined }))}
            />
          </div>
          <button type="button" onClick={agregarProducto} disabled={!selProd} className="inline-flex items-center gap-1 rounded-md bg-[#4FAEB2] px-3 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50">
            <Plus className="h-4 w-4" /> Agregar
          </button>
          <button type="button" onClick={agregarManual} className="inline-flex items-center gap-1 rounded-md border border-slate-300 px-3 py-2 text-sm text-slate-600 hover:bg-slate-50">
            <Plus className="h-4 w-4" /> Ítem manual
          </button>
        </div>

        {items.length === 0 ? (
          <p className="text-sm text-gray-500">Sin ítems. Agregá productos del inventario o ítems manuales.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-sm">
              <thead className="text-left text-xs text-gray-500 uppercase">
                <tr>
                  <th className="py-2 pr-2">Descripción</th>
                  <th className="py-2 px-2 w-20">Cant.</th>
                  <th className="py-2 px-2 w-32">Precio unit.</th>
                  <th className="py-2 px-2 w-24">IVA</th>
                  <th className="py-2 px-2 w-28">Descuento</th>
                  <th className="py-2 px-2 w-32 text-right">Total</th>
                  <th className="py-2 pl-2 w-10"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {items.map((it, i) => {
                  const t = itemTotals(it);
                  const abierto = !!expandido[i];
                  const tieneDetalle =
                    !!it.imagen_url || !!it.descripcion_comercial || !!it.especificaciones_tecnicas || !!it.caracteristicas_texto;
                  return (
                    <Fragment key={i}>
                    <tr>
                      <td className="py-2 pr-2">
                        <div className="flex items-center gap-1.5">
                          <button
                            type="button"
                            onClick={() => setExpandido((p) => ({ ...p, [i]: !p[i] }))}
                            className={`shrink-0 rounded p-1 hover:bg-slate-100 ${tieneDetalle ? "text-[#4FAEB2]" : "text-slate-400"}`}
                            aria-label="Detalle comercial"
                            title="Imagen y especificaciones técnicas"
                          >
                            <ChevronDown className={`h-4 w-4 transition-transform ${abierto ? "rotate-180" : ""}`} />
                          </button>
                          <input value={it.producto_nombre} onChange={(e) => updItem(i, { producto_nombre: e.target.value })} className={inputClass} placeholder="Descripción" />
                        </div>
                      </td>
                      <td className="py-2 px-2">
                        <input type="number" min="0" step="0.01" value={it.cantidad} onChange={(e) => updItem(i, { cantidad: Number(e.target.value) })} className={inputClass} />
                      </td>
                      <td className="py-2 px-2">
                        <input type="number" min="0" step="1" value={it.precio_unitario} onChange={(e) => updItem(i, { precio_unitario: Number(e.target.value) })} className={inputClass} />
                      </td>
                      <td className="py-2 px-2">
                        <select value={it.iva_tipo} onChange={(e) => updItem(i, { iva_tipo: e.target.value as IvaTipoPresupuesto })} className={`${inputClass} bg-white`}>
                          {IVAS.map((iv) => <option key={iv} value={iv}>{iv}</option>)}
                        </select>
                      </td>
                      <td className="py-2 px-2">
                        <input type="number" min="0" step="1" value={it.descuento} onChange={(e) => updItem(i, { descuento: Number(e.target.value) })} className={inputClass} />
                      </td>
                      <td className="py-2 px-2 text-right tabular-nums font-medium">{fmtGs(t.total)}</td>
                      <td className="py-2 pl-2 text-right">
                        <button onClick={() => delItem(i)} className="text-red-600 hover:text-red-700" aria-label="Eliminar"><Trash2 className="h-4 w-4" /></button>
                      </td>
                    </tr>
                    {abierto && (
                      <tr className="bg-slate-50/60">
                        <td colSpan={7} className="px-3 py-3">
                          <div className="grid grid-cols-1 lg:grid-cols-[160px_1fr] gap-4">
                            <div>
                              <label className={labelClass}><ImageIcon className="inline h-3.5 w-3.5 mr-1" />Imagen (URL)</label>
                              <input value={it.imagen_url ?? ""} onChange={(e) => updItem(i, { imagen_url: e.target.value })} className={inputClass} placeholder="https://…" />
                              {it.imagen_url ? (
                                // eslint-disable-next-line @next/next/no-img-element
                                <img src={it.imagen_url} alt="" className="mt-2 h-24 w-full rounded-md border border-slate-200 object-cover" />
                              ) : null}
                            </div>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                              <div className="sm:col-span-2">
                                <label className={labelClass}>Descripción comercial</label>
                                <textarea value={it.descripcion_comercial ?? ""} onChange={(e) => updItem(i, { descripcion_comercial: e.target.value })} rows={2} className={inputClass} placeholder="Texto comercial que verá el cliente" />
                              </div>
                              <div>
                                <label className={labelClass}>Especificaciones técnicas</label>
                                <textarea value={it.especificaciones_tecnicas ?? ""} onChange={(e) => updItem(i, { especificaciones_tecnicas: e.target.value })} rows={3} className={inputClass} placeholder="Detalle técnico" />
                              </div>
                              <div>
                                <label className={labelClass}>Características (una &laquo;clave: valor&raquo; por línea)</label>
                                <textarea value={it.caracteristicas_texto ?? ""} onChange={(e) => updItem(i, { caracteristicas_texto: e.target.value })} rows={3} className={inputClass} placeholder={"Potencia: 1500W\nGarantía: 12 meses"} />
                              </div>
                            </div>
                          </div>
                          <p className="mt-2 text-xs text-slate-500">Estos datos aparecen en el presupuesto. Al convertir a factura NO se copian al concepto fiscal.</p>
                        </td>
                      </tr>
                    )}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {items.length > 0 && (
          <div className="mt-4 ml-auto w-full sm:w-72 text-sm space-y-1">
            <div className="flex justify-between"><span className="text-gray-500">Subtotal (sin IVA)</span><span className="tabular-nums">{fmtGs(totales.subtotal)}</span></div>
            <div className="flex justify-between"><span className="text-gray-500">IVA</span><span className="tabular-nums">{fmtGs(totales.iva)}</span></div>
            {totales.desc > 0 && <div className="flex justify-between"><span className="text-gray-500">Descuentos</span><span className="tabular-nums">- {fmtGs(totales.desc)}</span></div>}
            <div className="flex justify-between border-t border-slate-200 pt-1 font-semibold text-base"><span>Total</span><span className="tabular-nums text-[#4FAEB2]">{fmtGs(totales.total)}</span></div>
          </div>
        )}
      </div>

      {/* Condiciones */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-sm p-5">
        <h2 className="text-sm font-semibold text-gray-700 mb-3">Condiciones comerciales</h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div>
            <label className={labelClass}>Moneda</label>
            <select value={moneda} onChange={(e) => setMoneda(e.target.value as "PYG" | "USD")} className={`${inputClass} bg-white`}>
              <option value="PYG">Guaraníes (PYG)</option>
              <option value="USD">Dólares (USD)</option>
            </select>
          </div>
          {moneda === "USD" && (
            <div>
              <label className={labelClass}>Tipo de cambio</label>
              <input type="number" min="0" step="0.01" value={tipoCambio} onChange={(e) => setTipoCambio(e.target.value)} className={inputClass} placeholder="Ej: 7500" />
            </div>
          )}
          <div>
            <label className={labelClass}>Validez (días)</label>
            <input type="number" min="0" value={validezDias} onChange={(e) => setValidezDias(e.target.value)} className={inputClass} />
          </div>
          <div>
            <label className={labelClass}>Forma de pago</label>
            <input value={formaPago} onChange={(e) => setFormaPago(e.target.value)} className={inputClass} placeholder="Ej: 50% anticipo, saldo contra entrega" />
          </div>
          <div>
            <label className={labelClass}>Plazo de entrega</label>
            <input value={plazoEntrega} onChange={(e) => setPlazoEntrega(e.target.value)} className={inputClass} placeholder="Ej: 5 días hábiles" />
          </div>
          <div className="sm:col-span-3">
            <label className={labelClass}>Condiciones comerciales (texto libre)</label>
            <textarea value={condiciones} onChange={(e) => setCondiciones(e.target.value)} rows={2} className={inputClass} placeholder="Garantía, términos, notas comerciales…" />
          </div>
          <div className="sm:col-span-3">
            <label className={labelClass}>Observaciones</label>
            <textarea value={observaciones} onChange={(e) => setObservaciones(e.target.value)} rows={3} className={inputClass} />
          </div>
        </div>
      </div>

      <div className="flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
        <Link href="/presupuestos" className="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-600 hover:bg-gray-50">
          Cancelar
        </Link>
        <button onClick={guardar} disabled={!valido || guardando} className="inline-flex items-center justify-center gap-1.5 rounded-md bg-[#4FAEB2] px-5 py-2 text-sm font-medium text-white hover:bg-[#3F8E91] disabled:opacity-50">
          {guardando ? <><Loader2 className="h-4 w-4 animate-spin" /> Guardando…</> : "Guardar presupuesto"}
        </button>
      </div>
    </div>
  );
}
