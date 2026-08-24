/**
 * Valida las matrices de acceso de los roles acotados contra la base real y
 * contra el mapa de rutas del ERP.
 *
 * Cubre las dos capas juntas:
 *   1. qué módulos tiene el usuario en `usuario_modulos`;
 *   2. qué módulo exige cada ruta (`pathRequiresModuleSlug`), que es lo que
 *      impide entrar por URL directa.
 *
 * Incluye la no-regresión: el administrador no debe perder accesos y el
 * Asistente Administrativo debe conservar los suyos tras el split de Inventario.
 */
import fs from "node:fs";
import { Client } from "pg";
import { pathRequiresModuleSlug, isModuleSlugGranted } from "@/lib/modulos/route-slug-map";

const SCHEMA = "tecnolabo";
const AUTH_ASISTENTE = "fa5dcbba-5675-4a4a-b574-648dc754e9bd";
const AUTH_VENDEDOR = "363904e6-8fd3-458f-996d-423f2b83c1a2";

const env: Record<string, string> = {};
for (const l of fs.readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const m = l.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) env[m[1]!] = m[2]!.replace(/^["']|["']$/g, "");
}

type Caso = { area: string; ruta: string; debe: boolean };

/** Vendedor: Comercial sin comisiones + Inventario solo productos y categorías. */
const MATRIZ_VENDEDOR: Caso[] = [
  { area: "Comercial · Clientes", ruta: "/clientes", debe: true },
  { area: "Comercial · Caja", ruta: "/ventas", debe: true },
  { area: "Comercial · Presupuestos", ruta: "/presupuestos", debe: true },
  { area: "Comercial · Notas de remisión", ruta: "/notas-remision", debe: true },
  { area: "Comercial · CRM", ruta: "/crm", debe: true },
  { area: "Comercial · COMISIONES", ruta: "/comisiones", debe: false },
  { area: "Inventario · Productos", ruta: "/inventario", debe: true },
  { area: "Inventario · Categorías", ruta: "/inventario/categorias", debe: true },
  { area: "Inventario · Movimientos", ruta: "/inventario/movimientos", debe: false },
  { area: "Inventario · Notas de salida", ruta: "/notas-salida", debe: false },
  { area: "Inventario · Alertas de stock", ruta: "/inventario/alertas", debe: false },
  { area: "Finanzas · Pagos", ruta: "/pagos", debe: false },
  { area: "Finanzas · Gastos", ruta: "/gastos", debe: false },
  { area: "Finanzas · Cuentas bancarias", ruta: "/configuracion/entidades-bancarias", debe: false },
  { area: "Finanzas · Recibos", ruta: "/recibos", debe: true },
  { area: "Finanzas · Cobranzas", ruta: "/cobranzas", debe: false },
  { area: "Compras · Órdenes", ruta: "/compras", debe: false },
  { area: "Compras · Proveedores", ruta: "/proveedores", debe: false },
  { area: "Compras · Cuentas por pagar", ruta: "/compras/cuentas-por-pagar", debe: false },
  { area: "Configuración", ruta: "/configuracion", debe: false },
  { area: "Usuarios", ruta: "/usuarios", debe: false },
  { area: "Reportes", ruta: "/reportes", debe: false },
];

/** Asistente: igual que antes del split de Inventario. */
const MATRIZ_ASISTENTE: Caso[] = [
  { area: "Comercial · Caja", ruta: "/ventas", debe: true },
  { area: "Comercial · COMISIONES", ruta: "/comisiones", debe: false },
  { area: "Finanzas · Pagos", ruta: "/pagos", debe: true },
  { area: "Finanzas · Gastos", ruta: "/gastos", debe: true },
  { area: "Finanzas · Cuentas bancarias", ruta: "/configuracion/entidades-bancarias", debe: true },
  { area: "Finanzas · Recibos", ruta: "/recibos", debe: true },
  { area: "Inventario · Productos", ruta: "/inventario", debe: true },
  { area: "Inventario · Categorías", ruta: "/inventario/categorias", debe: true },
  { area: "Inventario · Movimientos (conserva)", ruta: "/inventario/movimientos", debe: true },
  { area: "Inventario · Notas de salida (conserva)", ruta: "/notas-salida", debe: true },
  { area: "Inventario · Alertas (conserva)", ruta: "/inventario/alertas", debe: true },
  { area: "Compras · Órdenes", ruta: "/compras", debe: true },
  { area: "Configuración", ruta: "/configuracion", debe: false },
];

let fallos = 0;
function check(ok: boolean, msg: string) {
  console.log((ok ? "  OK    " : "  FALLA ") + msg);
  if (!ok) fallos++;
}

async function slugsDe(c: Client, authId: string): Promise<{ nombre: string; rol: string; slugs: Set<string> } | null> {
  const u = await c.query(
    `SELECT id, nombre, rol, activo FROM ${SCHEMA}.usuarios WHERE auth_user_id = $1::uuid`,
    [authId],
  );
  if (u.rowCount === 0) return null;
  const m = await c.query(
    `SELECT mo.slug FROM ${SCHEMA}.usuario_modulos um
       JOIN ${SCHEMA}.modulos mo ON mo.id = um.modulo_id
      WHERE um.usuario_id = $1::uuid`,
    [u.rows[0].id],
  );
  return {
    nombre: String(u.rows[0].nombre),
    rol: String(u.rows[0].rol),
    slugs: new Set(m.rows.map((r) => String(r.slug))),
  };
}

function correr(titulo: string, slugs: Set<string>, matriz: Caso[]) {
  console.log("");
  console.log("── " + titulo + " ──");
  for (const m of matriz) {
    const slug = pathRequiresModuleSlug(m.ruta);
    if (!slug) {
      check(false, m.area + " → " + m.ruta + " NO exige modulo (se entra por URL)");
      continue;
    }
    // strict: la instancia corre en single_client, sin alias heredados.
    const puede = isModuleSlugGranted(slug, slugs, undefined, { strict: true });
    check(puede === m.debe, m.area + " → " + (m.debe ? "SI" : "NO") + " (slug " + slug + ")");
  }
}

(async () => {
  const c = new Client({ connectionString: env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } });
  await c.connect();
  try {
    const vend = await slugsDe(c, AUTH_VENDEDOR);
    const asis = await slugsDe(c, AUTH_ASISTENTE);

    if (!vend) { console.log("FALLA: el vendedor no tiene ficha ERP"); process.exit(1); }
    if (!asis) { console.log("FALLA: el asistente no tiene ficha ERP"); process.exit(1); }

    console.log("Vendedor : " + vend.nombre + " (rol=" + vend.rol + ") · " + vend.slugs.size + " modulos");
    console.log("Asistente: " + asis.nombre + " (rol=" + asis.rol + ") · " + asis.slugs.size + " modulos");
    check(vend.rol !== "admin" && vend.rol !== "administrador", "el vendedor no es administrador");

    correr("VENDEDOR / ÁREA COMERCIAL", vend.slugs, MATRIZ_VENDEDOR);
    correr("ASISTENTE ADMINISTRATIVO (no regresion)", asis.slugs, MATRIZ_ASISTENTE);

    console.log("");
    console.log("── administrador ──");
    const admin = await c.query(
      `SELECT id FROM ${SCHEMA}.usuarios WHERE lower(rol) IN ('admin','administrador','super_admin') LIMIT 1`,
    );
    check((admin.rowCount ?? 0) > 0, "existe un usuario administrador");
    if ((admin.rowCount ?? 0) > 0) {
      const n = await c.query(
        `SELECT count(*)::int n FROM ${SCHEMA}.usuario_modulos WHERE usuario_id = $1::uuid`,
        [admin.rows[0].id],
      );
      check(n.rows[0].n === 0, "el administrador NO quedo acotado (ve todos los modulos)");
    }
    const off = await c.query(`SELECT count(*)::int n FROM ${SCHEMA}.empresa_modulos WHERE activo = false`);
    check(off.rows[0].n === 0, "ningun modulo de la empresa quedo desactivado");
  } finally {
    await c.end();
  }

  console.log("");
  if (fallos > 0) {
    console.log("RESULTADO: " + fallos + " comprobacion(es) fallaron");
    process.exit(1);
  }
  console.log("RESULTADO: matrices de acceso correctas");
})();
