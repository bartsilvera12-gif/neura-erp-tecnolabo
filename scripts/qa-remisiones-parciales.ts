/**
 * QA de entregas parciales Factura → Nota de Remisión (Tecnolabo).
 * Ejercita el flujo REAL (funciones de remisiones-pg) contra la base, crea datos
 * de prueba marcados y los BORRA al final. Solo schema tecnolabo.
 *
 * Correr:  node_modules/.bin/tsx scripts/qa-remisiones-parciales.ts
 */
import * as fs from "fs";
import { Pool } from "pg";

// Cargar .env.local ANTES de importar el código (para SUPABASE_DB_URL / SUPABASE_APP_SCHEMA).
for (const line of fs.readFileSync(".env.local", "utf8").split("\n")) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, "");
}

const SCHEMA = "tecnolabo";
const EMPRESA = "2473b6f2-b0c4-4c20-ade7-3cd581a5327b";
const CLIENTE = "3b4e7dee-5f04-40c0-8db7-2e665fdfd65d";
const TAG = "QAREM";

const pool = new Pool({ connectionString: process.env.SUPABASE_DB_URL });
const created = { productos: [] as string[], facturas: [] as string[], remisiones: [] as string[] };

let pass = 0, fail = 0;
function assert(cond: boolean, msg: string) {
  if (cond) { pass++; console.log("  ✓ " + msg); }
  else { fail++; console.log("  ✗ FAIL: " + msg); }
}
async function q(sql: string, params: unknown[] = []) { return pool.query(sql, params); }
async function stock(id: string) { return Number((await q(`SELECT stock_actual FROM ${SCHEMA}.productos WHERE id=$1`, [id])).rows[0].stock_actual); }
async function entregada(id: string) { return Number((await q(`SELECT cantidad_entregada FROM ${SCHEMA}.factura_items WHERE id=$1`, [id])).rows[0].cantidad_entregada); }
async function estadoEntrega(id: string) { return String((await q(`SELECT estado_entrega FROM ${SCHEMA}.facturas WHERE id=$1`, [id])).rows[0].estado_entrega); }
async function facturaSnap(id: string) { return (await q(`SELECT monto, (SELECT json_agg(json_build_object('d',descripcion,'c',cantidad) ORDER BY created_at) FROM ${SCHEMA}.factura_items WHERE factura_id=$1) items FROM ${SCHEMA}.facturas WHERE id=$1`, [id])).rows[0]; }

async function nuevoProducto(nombre: string, stockInicial: number) {
  const r = await q(`INSERT INTO ${SCHEMA}.productos (empresa_id, nombre, sku, stock_actual, controla_stock, precio_venta, costo_promedio) VALUES ($1,$2,$3,$4,true,1000,500) RETURNING id`, [EMPRESA, `${TAG} ${nombre}`, `${TAG}-${nombre}-${Date.now()}${Math.floor(Math.random()*1000)}`, stockInicial]);
  created.productos.push(r.rows[0].id); return r.rows[0].id as string;
}
async function nuevaFactura(lineas: { prodId: string; desc: string; cant: number }[]) {
  const monto = lineas.reduce((s, l) => s + l.cant * 1000, 0);
  const f = await q(`INSERT INTO ${SCHEMA}.facturas (empresa_id, cliente_id, numero_factura, fecha, fecha_vencimiento, monto, tipo) VALUES ($1,$2,$3, now(), now(), $4, 'contado') RETURNING id`, [EMPRESA, CLIENTE, `${TAG}-${Date.now()}${Math.floor(Math.random()*1000)}`, monto]);
  const facturaId = f.rows[0].id as string; created.facturas.push(facturaId);
  const items: Record<string, string> = {};
  for (const l of lineas) {
    const it = await q(`INSERT INTO ${SCHEMA}.factura_items (factura_id, empresa_id, descripcion, cantidad, precio_unitario, subtotal, total, producto_id, sku) VALUES ($1,$2,$3,$4,1000,$5,$5,$6,$7) RETURNING id`, [facturaId, EMPRESA, l.desc, l.cant, l.cant * 1000, l.prodId, `${TAG}`]);
    items[l.desc] = it.rows[0].id;
  }
  return { facturaId, items };
}

async function main() {
  const rem = await import("../src/lib/ventas/server/remisiones-pg");
  const usuario = { id: null, nombre: "QA Bot", email: "qa@test.local" };
  const line = (r: Record<string, string>, resumen: Awaited<ReturnType<typeof rem.getResumenFacturaEntrega>>, desc: string, cant: number) => {
    const l = resumen!.lineas.find((x) => x.factura_item_id === r[desc])!;
    return { factura_item_id: l.factura_item_id, producto_id: l.producto_id, producto_nombre: l.producto_nombre, sku: l.sku, cantidad: cant, costo_unitario: l.costo_unitario };
  };

  const P1 = await nuevoProducto("P1", 100);
  const P2 = await nuevoProducto("P2", 100);

  // ── T1: Factura 10 → remisión total (10) confirmada ──────────────────────────
  console.log("\n[T1] Factura 10 → remisión de 10 (todo), confirmada");
  {
    const { facturaId, items } = await nuevaFactura([{ prodId: P1, desc: "A", cant: 6 }, { prodId: P2, desc: "B", cant: 4 }]);
    const res = await rem.getResumenFacturaEntrega(SCHEMA, EMPRESA, facturaId);
    const s1 = await stock(P1), s2 = await stock(P2);
    const out = await rem.crearRemision(SCHEMA, EMPRESA, { factura_id: facturaId, items: [line(items, res, "A", 6), line(items, res, "B", 4)], confirmar: true }, usuario);
    created.remisiones.push(out.remision_id);
    assert(await entregada(items.A) === 6 && await entregada(items.B) === 4, "cantidad_entregada = facturado");
    assert(await estadoEntrega(facturaId) === "entregada", "estado_entrega = entregada");
    assert(await stock(P1) === s1 - 6 && await stock(P2) === s2 - 4, "stock descontado por remisión");
  }

  // ── T2/T3/T4/T11: parciales + segunda remisión + excedente ───────────────────
  console.log("\n[T2/T3] Factura 10 → remisión 7, luego 3 restantes");
  const F2 = await nuevaFactura([{ prodId: P1, desc: "A", cant: 5 }, { prodId: P2, desc: "B", cant: 5 }]);
  {
    let res = await rem.getResumenFacturaEntrega(SCHEMA, EMPRESA, F2.facturaId);
    const s1 = await stock(P1), s2 = await stock(P2);
    const r1 = await rem.crearRemision(SCHEMA, EMPRESA, { factura_id: F2.facturaId, items: [line(F2.items, res, "A", 5), line(F2.items, res, "B", 2)], confirmar: true }, usuario);
    created.remisiones.push(r1.remision_id);
    assert(await entregada(F2.items.A) === 5 && await entregada(F2.items.B) === 2, "T2: entregado A=5, B=2");
    assert(await estadoEntrega(F2.facturaId) === "parcialmente_entregada", "T2: estado = parcialmente_entregada");
    assert(await stock(P1) === s1 - 5 && await stock(P2) === s2 - 2, "T2: stock -5/-2");

    res = await rem.getResumenFacturaEntrega(SCHEMA, EMPRESA, F2.facturaId);
    assert(res!.lineas.find((l) => l.factura_item_id === F2.items.B)!.disponible === 3, "T3: pendiente B = 3");
    const r2 = await rem.crearRemision(SCHEMA, EMPRESA, { factura_id: F2.facturaId, items: [line(F2.items, res, "B", 3)], confirmar: true }, usuario);
    created.remisiones.push(r2.remision_id);
    assert(await entregada(F2.items.B) === 5, "T3: entregado B = 5 (completo)");
    assert(await estadoEntrega(F2.facturaId) === "entregada", "T3: estado = entregada");
  }

  console.log("\n[T4/T11] Intentar remitir más de lo pendiente (debe fallar)");
  {
    const res = await rem.getResumenFacturaEntrega(SCHEMA, EMPRESA, F2.facturaId);
    let lanzo = false;
    try { await rem.crearRemision(SCHEMA, EMPRESA, { factura_id: F2.facturaId, items: [{ ...line(F2.items, res, "A", 1) }], confirmar: true }, usuario); }
    catch (e) { lanzo = e instanceof rem.RemisionExcedenteError; }
    assert(lanzo, "T4: rechaza remitir sobre saldo 0 (RemisionExcedenteError)");
  }

  // ── T5/T6: editar BORRADOR (quitar ítem, cambiar cantidad) ───────────────────
  console.log("\n[T5/T6] Editar borrador: quitar ítem y cambiar cantidad");
  {
    const F = await nuevaFactura([{ prodId: P1, desc: "A", cant: 5 }, { prodId: P2, desc: "B", cant: 5 }]);
    const res = await rem.getResumenFacturaEntrega(SCHEMA, EMPRESA, F.facturaId);
    const s1 = await stock(P1);
    const r = await rem.crearRemision(SCHEMA, EMPRESA, { factura_id: F.facturaId, items: [line(F.items, res, "A", 5), line(F.items, res, "B", 5)], confirmar: false }, usuario);
    created.remisiones.push(r.remision_id);
    // Quitar B (poner 0), dejar A:5
    await rem.editarRemision(SCHEMA, EMPRESA, r.remision_id, { items: [line(F.items, res, "A", 5)] }, usuario);
    let its = (await q(`SELECT factura_item_id, cantidad FROM ${SCHEMA}.notas_remision_items WHERE remision_id=$1`, [r.remision_id])).rows;
    assert(its.length === 1 && its[0].factura_item_id === F.items.A && Number(its[0].cantidad) === 5, "T5: quitar B → queda solo A:5");
    assert(await stock(P1) === s1, "T5: borrador NO mueve stock");
    // Cambiar A 5→3
    await rem.editarRemision(SCHEMA, EMPRESA, r.remision_id, { items: [line(F.items, res, "A", 3)] }, usuario);
    its = (await q(`SELECT cantidad FROM ${SCHEMA}.notas_remision_items WHERE remision_id=$1`, [r.remision_id])).rows;
    assert(Number(its[0].cantidad) === 3, "T6: cambiar A 5→3 en borrador");
    assert(await entregada(F.items.A) === 0, "T6: borrador no afecta cantidad_entregada");
    // Confirmar → ahora sí descuenta 3
    await rem.confirmarRemision(SCHEMA, EMPRESA, r.remision_id, usuario);
    assert(await entregada(F.items.A) === 3 && await stock(P1) === s1 - 3, "T6: al confirmar descuenta 3");
  }

  // ── T7/T8/T9/T10: editar CONFIRMADA con ajuste por diferencia ────────────────
  console.log("\n[T7] Editar remisión confirmada: 7→5 devuelve 2, 5→9 saca 4 más");
  const F3 = await nuevaFactura([{ prodId: P1, desc: "A", cant: 10 }]);
  {
    const res = await rem.getResumenFacturaEntrega(SCHEMA, EMPRESA, F3.facturaId);
    const s0 = await stock(P1);
    const r = await rem.crearRemision(SCHEMA, EMPRESA, { factura_id: F3.facturaId, items: [line(F3.items, res, "A", 7)], confirmar: true }, usuario);
    created.remisiones.push(r.remision_id);
    assert(await stock(P1) === s0 - 7 && await entregada(F3.items.A) === 7, "T7: confirmada descuenta 7");
    // Editar 7 → 5 (devolver 2)
    await rem.editarRemision(SCHEMA, EMPRESA, r.remision_id, { items: [line(F3.items, res, "A", 5)] }, usuario);
    assert(await stock(P1) === s0 - 5, "T7: 7→5 devuelve 2 al stock (ajuste por diferencia)");
    assert(await entregada(F3.items.A) === 5, "T7: cantidad_entregada = 5");
    assert(await estadoEntrega(F3.facturaId) === "parcialmente_entregada", "T7: estado recalculado = parcial");
    // Editar 5 → 9 (sacar 4 más)
    await rem.editarRemision(SCHEMA, EMPRESA, r.remision_id, { items: [line(F3.items, res, "A", 9)] }, usuario);
    assert(await stock(P1) === s0 - 9 && await entregada(F3.items.A) === 9, "T7: 5→9 saca 4 más");
    // Excedente al editar confirmada (9 → 11 sobre facturado 10)
    let lanzo = false;
    try { await rem.editarRemision(SCHEMA, EMPRESA, r.remision_id, { items: [line(F3.items, res, "A", 11)] }, usuario); } catch (e) { lanzo = e instanceof rem.RemisionExcedenteError; }
    assert(lanzo, "T7: editar por encima del facturado (11>10) rechazado");
    // Cantidad de movimientos: 1 SALIDA(7) + 1 ENTRADA(2) + 1 SALIDA(4) = 3, sin regenerar todo
    const movs = (await q(`SELECT count(*)::int n FROM ${SCHEMA}.movimientos_inventario WHERE documento_tipo='remision' AND documento_id=$1 AND anulado_at IS NULL AND origen<>'anulacion'`, [r.remision_id])).rows[0].n;
    assert(movs === 3, "T7: ajustes por diferencia (3 movimientos incrementales, no regenerados)");
  }

  // ── T8: la factura nunca cambia ──────────────────────────────────────────────
  console.log("\n[T8] La factura permanece intacta");
  {
    const snap = await facturaSnap(F3.facturaId);
    assert(Number(snap.monto) === 10000, "T8: monto de factura intacto");
    assert(snap.items.length === 1 && Number(snap.items[0].c) === 10, "T8: ítems/cantidades de factura intactos (10)");
  }

  // ── T12: aislamiento por empresa (no acceso cruzado) ─────────────────────────
  console.log("\n[T12] Aislamiento: otra empresa no ve la factura");
  {
    const otra = await rem.getResumenFacturaEntrega(SCHEMA, "00000000-0000-0000-0000-000000000000", F3.facturaId);
    assert(otra === null, "T12: getResumen con empresa_id ajeno → null (RLS/empresa_id en query)");
  }

  console.log(`\n=== RESULTADO: ${pass} PASS, ${fail} FAIL ===`);
}

async function cleanup() {
  try {
    for (const rid of created.remisiones) {
      await q(`DELETE FROM ${SCHEMA}.notas_remision_items WHERE remision_id=$1`, [rid]);
      await q(`DELETE FROM ${SCHEMA}.auditoria_eventos WHERE entidad='remision' AND entidad_id=$1`, [rid]).catch(() => null);
    }
    if (created.remisiones.length) await q(`DELETE FROM ${SCHEMA}.notas_remision WHERE id = ANY($1::uuid[])`, [created.remisiones]);
    if (created.productos.length) await q(`DELETE FROM ${SCHEMA}.movimientos_inventario WHERE producto_id = ANY($1::uuid[])`, [created.productos]);
    for (const fid of created.facturas) await q(`DELETE FROM ${SCHEMA}.factura_items WHERE factura_id=$1`, [fid]);
    if (created.facturas.length) await q(`DELETE FROM ${SCHEMA}.facturas WHERE id = ANY($1::uuid[])`, [created.facturas]);
    if (created.productos.length) await q(`DELETE FROM ${SCHEMA}.productos WHERE id = ANY($1::uuid[])`, [created.productos]);
    // Reset del correlativo REM (no hay remisiones reales: la 1ª real quedará en REM-000001).
    await q(`DELETE FROM ${SCHEMA}.documento_correlativos WHERE empresa_id=$1 AND tipo='remision'`, [EMPRESA]).catch(() => null);
    console.log("Cleanup OK (datos de prueba borrados).");
  } catch (e) { console.error("Cleanup ERROR:", (e as Error).message); }
}

main().catch((e) => { console.error("ERROR:", e); fail++; }).finally(async () => {
  await cleanup();
  await pool.end();
  process.exit(fail > 0 ? 1 : 0);
});
