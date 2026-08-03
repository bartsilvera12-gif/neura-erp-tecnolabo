/**
 * Notas de salida (Fase 4).
 *
 * Salida de inventario no necesariamente ligada a una factura. El stock se
 * descuenta SOLO al CONFIRMAR, usando el helper canónico de F0. No permite stock
 * negativo salvo que la empresa lo autorice (empresa_config.permitir_stock_negativo).
 * La anulación repone con movimientos inversos sin borrar historial.
 */
import type { PoolClient } from "pg";
import { getChatPostgresPool, quoteSchemaTable } from "@/lib/supabase/chat-pg-pool";
import { assertAllowedChatDataSchema } from "@/lib/supabase/chat-data-schema";
import {
  registrarMovimientoInventarioTx,
  revertirMovimientosDeDocumentoTx,
  StockInsuficienteMovimientoError,
} from "@/lib/inventario/server/stock-core-pg";
import { getEmpresaConfigTx } from "@/lib/config/server/empresa-config-pg";
import { siguienteCorrelativoTx } from "@/lib/documentos/server/correlativo-pg";
import { registrarAuditoriaTx } from "@/lib/auditoria/server/auditoria-pg";

export const MOTIVOS_NOTA_SALIDA = [
  "uso_interno",
  "muestra",
  "prestamo",
  "daño",
  "perdida",
  "consumo",
  "ajuste",
  "otro",
] as const;
export type MotivoNotaSalida = (typeof MOTIVOS_NOTA_SALIDA)[number];

export { StockInsuficienteMovimientoError };

export interface NotaSalidaItemInput {
  producto_id: string;
  producto_nombre: string;
  sku?: string | null;
  cantidad: number;
  costo_unitario?: number;
  observacion?: string | null;
}

export interface CrearNotaSalidaInput {
  motivo: string;
  deposito_id?: string | null;
  sucursal_id?: string | null;
  observacion?: string | null;
  items: NotaSalidaItemInput[];
  confirmar?: boolean;
}

export interface Usuario {
  id?: string | null;
  nombre?: string | null;
  email?: string | null;
}

function pool() {
  const p = getChatPostgresPool();
  if (!p) throw new Error("Pool no disponible.");
  return p;
}

async function confirmarNotaSalidaTx(
  client: PoolClient,
  schema: string,
  empresaId: string,
  notaId: string,
  usuario: Usuario,
): Promise<void> {
  const tNS = quoteSchemaTable(schema, "notas_salida");
  const tItems = quoteSchemaTable(schema, "notas_salida_items");

  const ns = await client.query(`SELECT * FROM ${tNS} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [notaId, empresaId]);
  if (ns.rowCount === 0) throw new Error("Nota de salida no encontrada.");
  const nota = ns.rows[0];
  if (nota.estado !== "borrador") throw new Error(`La nota no está en borrador (estado: ${nota.estado}).`);

  const cfg = await getEmpresaConfigTx(client, schema, empresaId);
  const items = await client.query(`SELECT * FROM ${tItems} WHERE nota_salida_id = $1::uuid ORDER BY created_at`, [notaId]);

  for (const it of items.rows) {
    const cantidad = Number(it.cantidad) || 0;
    if (cantidad <= 0) continue;
    await registrarMovimientoInventarioTx(
      client,
      schema,
      {
        empresaId,
        productoId: it.producto_id,
        productoNombre: it.producto_nombre,
        productoSku: it.sku ?? "",
        tipo: "SALIDA",
        cantidad,
        costoUnitario: Number(it.costo_unitario) || 0,
        origen: "nota_salida",
        referencia: nota.numero,
        documentoTipo: "nota_salida",
        documentoId: notaId,
        depositoId: nota.deposito_id ?? null,
        sucursalId: nota.sucursal_id ?? null,
        observacion: it.observacion ?? null,
        usuarioId: usuario.id ?? null,
        usuarioNombre: usuario.nombre ?? null,
      },
      { permitirStockNegativo: cfg.permitir_stock_negativo, onInsuficiente: "throw" },
    );
  }

  await client.query(
    `UPDATE ${tNS}
        SET estado = 'confirmada', confirmada_at = now(),
            usuario_confirmador_id = $1::uuid, usuario_confirmador_nombre = $2, updated_at = now()
      WHERE id = $3::uuid`,
    [usuario.id ?? null, usuario.nombre ?? null, notaId],
  );

  await registrarAuditoriaTx(client, schema, {
    empresaId,
    entidad: "nota_salida",
    entidadId: notaId,
    accion: "confirmar",
    origen: "api/notas-salida",
    usuarioId: usuario.id ?? null,
    usuarioEmail: usuario.email ?? null,
    usuarioNombre: usuario.nombre ?? null,
    detalle: { numero: nota.numero, motivo: nota.motivo },
  });
}

export async function crearNotaSalida(
  schema: string,
  empresaId: string,
  input: CrearNotaSalidaInput,
  usuario: Usuario,
): Promise<{ nota_salida_id: string; numero: string; confirmada: boolean }> {
  assertAllowedChatDataSchema(schema);
  const tNS = quoteSchemaTable(schema, "notas_salida");
  const tItems = quoteSchemaTable(schema, "notas_salida_items");
  if (!input.items || input.items.length === 0) throw new Error("La nota de salida no tiene ítems.");
  const motivo = (MOTIVOS_NOTA_SALIDA as readonly string[]).includes(input.motivo) ? input.motivo : "otro";

  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const { numero } = await siguienteCorrelativoTx(client, schema, empresaId, "nota_salida", { prefijo: "NS" });

    const ns = await client.query(
      `INSERT INTO ${tNS} (
         empresa_id, numero, motivo, deposito_id, sucursal_id, observacion, estado,
         usuario_creador_id, usuario_creador_nombre
       ) VALUES ($1::uuid, $2, $3, $4::uuid, $5::uuid, $6, 'borrador', $7::uuid, $8) RETURNING id`,
      [empresaId, numero, motivo, input.deposito_id ?? null, input.sucursal_id ?? null, input.observacion ?? null, usuario.id ?? null, usuario.nombre ?? null],
    );
    const notaId = ns.rows[0].id as string;

    for (const it of input.items) {
      await client.query(
        `INSERT INTO ${tItems} (empresa_id, nota_salida_id, producto_id, producto_nombre, sku, cantidad, costo_unitario, observacion)
           VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6::numeric, $7::numeric, $8)`,
        [empresaId, notaId, it.producto_id, it.producto_nombre, it.sku ?? null, Number(it.cantidad) || 0, Number(it.costo_unitario) || 0, it.observacion ?? null],
      );
    }

    if (input.confirmar) {
      await confirmarNotaSalidaTx(client, schema, empresaId, notaId, usuario);
    }

    await client.query("COMMIT");
    return { nota_salida_id: notaId, numero, confirmada: !!input.confirmar };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export async function confirmarNotaSalida(schema: string, empresaId: string, notaId: string, usuario: Usuario): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    await confirmarNotaSalidaTx(client, schema, empresaId, notaId, usuario);
    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export async function anularNotaSalida(schema: string, empresaId: string, notaId: string, usuario: Usuario, motivo: string): Promise<void> {
  assertAllowedChatDataSchema(schema);
  const tNS = quoteSchemaTable(schema, "notas_salida");
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const ns = await client.query(`SELECT * FROM ${tNS} WHERE id = $1::uuid AND empresa_id = $2::uuid FOR UPDATE`, [notaId, empresaId]);
    if (ns.rowCount === 0) throw new Error("Nota de salida no encontrada.");
    const nota = ns.rows[0];
    if (nota.estado !== "confirmada") throw new Error(`Solo se anula una nota confirmada (estado: ${nota.estado}).`);

    await revertirMovimientosDeDocumentoTx(client, schema, {
      empresaId,
      documentoTipo: "nota_salida",
      documentoId: notaId,
      usuarioId: usuario.id ?? null,
      usuarioNombre: usuario.nombre ?? null,
      motivo: `Anulación nota de salida ${nota.numero}: ${motivo}`,
    });

    await client.query(
      `UPDATE ${tNS} SET estado = 'anulada', anulada_at = now(), anulada_por = $1::uuid, anulada_motivo = $2, updated_at = now() WHERE id = $3::uuid`,
      [usuario.id ?? null, motivo, notaId],
    );

    await registrarAuditoriaTx(client, schema, {
      empresaId,
      entidad: "nota_salida",
      entidadId: notaId,
      accion: "anular",
      origen: "api/notas-salida",
      usuarioId: usuario.id ?? null,
      usuarioEmail: usuario.email ?? null,
      usuarioNombre: usuario.nombre ?? null,
      detalle: { numero: nota.numero, motivo },
    });

    await client.query("COMMIT");
  } catch (e) {
    await client.query("ROLLBACK").catch(() => null);
    throw e;
  } finally {
    client.release();
  }
}

export interface NotaSalidaResumen {
  id: string;
  numero: string;
  motivo: string;
  estado: string;
  fecha: string;
  usuario_creador_nombre: string | null;
  total_items: number;
}

export async function listNotasSalida(schema: string, empresaId: string): Promise<NotaSalidaResumen[]> {
  assertAllowedChatDataSchema(schema);
  const tNS = quoteSchemaTable(schema, "notas_salida");
  const tItems = quoteSchemaTable(schema, "notas_salida_items");
  const p = pool();
  const client = await p.connect();
  try {
    const res = await client.query(
      `SELECT n.id, n.numero, n.motivo, n.estado, n.fecha, n.usuario_creador_nombre,
              (SELECT COUNT(*) FROM ${tItems} i WHERE i.nota_salida_id = n.id)::int AS total_items
         FROM ${tNS} n WHERE n.empresa_id = $1::uuid ORDER BY n.created_at DESC`,
      [empresaId],
    );
    return res.rows as NotaSalidaResumen[];
  } finally {
    client.release();
  }
}

export async function getNotaSalida(schema: string, empresaId: string, notaId: string) {
  assertAllowedChatDataSchema(schema);
  const tNS = quoteSchemaTable(schema, "notas_salida");
  const tItems = quoteSchemaTable(schema, "notas_salida_items");
  const p = pool();
  const client = await p.connect();
  try {
    const nota = await client.query(`SELECT * FROM ${tNS} WHERE id = $1::uuid AND empresa_id = $2::uuid`, [notaId, empresaId]);
    if (nota.rowCount === 0) return null;
    const items = await client.query(`SELECT * FROM ${tItems} WHERE nota_salida_id = $1::uuid ORDER BY created_at`, [notaId]);
    return { nota: nota.rows[0], items: items.rows };
  } finally {
    client.release();
  }
}
