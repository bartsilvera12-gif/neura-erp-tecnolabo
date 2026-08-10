/** Prueba el fallback real de descripción del producto en ítems de presupuesto. */
import * as fs from "fs";
for (const line of fs.readFileSync(".env.local", "utf8").split("\n")) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, "");
}
(async () => {
  const { createClient } = await import("@supabase/supabase-js");
  const { aplicarFallbackDescripcionProducto } = await import("../src/lib/inventario/imagen-storage");
  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
    db: { schema: "tecnolabo" }, auth: { persistSession: false },
  });
  const EMP = "2473b6f2-b0c4-4c20-ade7-3cd581a5327b";
  const { data: prod } = await supabase.from("productos").select("id, descripcion").eq("sku", "TEC-00013").single();
  console.log("Producto TEC-00013 → descripcion (primeras líneas):");
  console.log("  " + String(prod!.descripcion).split("\n").slice(0, 2).join(" / "));

  const items: Array<Record<string, unknown>> = [
    { producto_id: prod!.id, descripcion_comercial: null, especificaciones_tecnicas: null, caracteristicas: [] }, // presupuesto viejo
    { producto_id: prod!.id, descripcion_comercial: "SNAPSHOT PROPIO", especificaciones_tecnicas: null, caracteristicas: [] }, // ya tiene snapshot
    { producto_id: null, descripcion_comercial: null }, // ítem manual
  ];
  await aplicarFallbackDescripcionProducto(supabase as never, EMP, items);

  let pass = 0, fail = 0;
  const A = (c: boolean, m: string) => { if (c) { pass++; console.log("  ✓ " + m); } else { fail++; console.log("  ✗ FAIL: " + m); } };
  console.log("\nTras aplicar el fallback:");
  A(items[0].descripcion_comercial === prod!.descripcion, "ítem sin snapshot → rellenó con la descripción real del producto (características)");
  A(items[1].descripcion_comercial === "SNAPSHOT PROPIO", "ítem con snapshot propio → NO se pisa");
  A(items[2].descripcion_comercial == null, "ítem manual sin producto → sigue sin detalle");
  console.log(`\n=== ${pass} PASS, ${fail} FAIL ===`);
  process.exit(fail > 0 ? 1 : 0);
})().catch((e) => { console.error("ERROR:", e.message); process.exit(1); });
