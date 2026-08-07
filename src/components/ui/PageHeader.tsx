import Link from "next/link";
import type { ReactNode } from "react";

/**
 * Encabezado de página estándar del ERP.
 *
 * Unifica el patrón repetido en cada módulo (eyebrow turquesa + título +
 * descripción + acción principal a la derecha). Base blanca, acento turquesa
 * (#1E2125 / var(--primary)).
 */
export default function PageHeader({
  eyebrow,
  title,
  description,
  actions,
  backHref,
  backLabel = "Volver",
}: {
  /** Texto pequeño en mayúsculas sobre el título (ej. "Zentra · Reportes"). */
  eyebrow?: string;
  title: string;
  description?: string;
  /** Acciones a la derecha (botones, export/import…). */
  actions?: ReactNode;
  /** Si se pasa, muestra un enlace "← Volver" arriba del eyebrow. */
  backHref?: string;
  backLabel?: string;
}) {
  return (
    <div>
      {backHref ? (
        <Link
          href={backHref}
          className="mb-2 inline-flex items-center gap-1 text-xs font-medium text-slate-500 transition-colors hover:text-[#17191C]"
        >
          <span aria-hidden>←</span> {backLabel}
        </Link>
      ) : null}
      <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-start sm:justify-between">
        <div className="min-w-0">
          {eyebrow ? (
            <div className="flex items-center gap-2">
              <span
                aria-hidden
                className="inline-block h-1.5 w-1.5 shrink-0 rounded-full bg-[#1E2125]"
                style={{ boxShadow: "0 0 0 3px rgba(30, 33, 37, 0.18)" }}
              />
              <p className="truncate text-[11px] font-semibold uppercase tracking-[0.18em] text-[#17191C]">
                {eyebrow}
              </p>
            </div>
          ) : null}
          <h1 className="mt-1 text-xl font-semibold tracking-tight text-slate-900">{title}</h1>
          {description ? (
            <p className="mt-1 max-w-2xl text-sm text-slate-500">{description}</p>
          ) : null}
        </div>
        {actions ? (
          <div className="flex flex-wrap items-center gap-2 sm:justify-end">{actions}</div>
        ) : null}
      </div>
    </div>
  );
}
