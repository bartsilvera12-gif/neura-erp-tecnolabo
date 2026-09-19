-- =============================================================================
-- Diagnóstico del rechazo SET «El hash del código QR incluido el de la cadena
-- de caracteres es inválido», desde el SQL Editor (sin necesidad del proyecto
-- instalado localmente).
--
-- Equivale a `npm run sifen:diagnosticar-qr`: prueba el CSC configurado en
-- todas sus variantes de caja contra IdCSC 0001 y 0002, y dice cuál reproduce
-- el `cHashQR` que quedó dentro del XML firmado. El CSC NO se imprime: solo
-- sus primeros 4 caracteres y su longitud.
--
-- Cómo completar los dos valores de abajo:
--   1. Abrir el XML firmado del documento rechazado
--      (/api/facturas/{factura_id}/sifen/documento).
--   2. Copiar el contenido de <dCarQR>. Tiene esta forma:
--        https://ekuatia.set.gov.py/consultas/qr?<CADENA>&cHashQR=<HASH>
--   3. `base`         = <CADENA> recortada JUSTO después de `IdCSC=`
--                       (sin los 4 dígitos del IdCSC: los agrega la consulta).
--      `hash_del_xml` = <HASH>.
--
-- Lectura del resultado:
--   coincide = true con id_csc 0002 → el CSC cargado es el CSC2 y se está
--       enviando IdCSC=0001: corregir el ID del CSC en la configuración.
--   coincide = true con id_csc 0001 y etiqueta distinta de 'tal cual' → el CSC
--       se cargó con la caja cambiada: volver a cargarlo como lo entrega el SET.
--   coincide = true con id_csc 0001 y 'tal cual' → el hash se calcula bien y el
--       CSC cargado es el que se usó: entonces ESE CSC no es el que el SET tiene
--       registrado para el timbrado. Verificarlo/regenerarlo en Marangatu.
--   ninguna fila true → el documento se firmó con un CSC distinto al que hoy
--       está configurado. Cargar el correcto, regenerar, firmar y enviar.
-- =============================================================================

WITH q AS (
  SELECT
    'PEGAR_AQUI_LA_CADENA_HASTA_IdCSC='                       AS base,
    'PEGAR_AQUI_EL_cHashQR'                                   AS hash_del_xml,
    'PEGAR_AQUI_EL_empresa_id'::uuid                          AS empresa_id
),
cand AS (
  SELECT v.etiqueta, v.valor
    FROM tecnolabo.empresa_sifen_config cfg, q
    CROSS JOIN LATERAL (VALUES
      ('tal cual',   btrim(cfg.csc)),
      ('MAYUSCULAS', upper(btrim(cfg.csc))),
      ('minusculas', lower(btrim(cfg.csc)))
    ) AS v(etiqueta, valor)
   WHERE cfg.empresa_id = q.empresa_id
     AND coalesce(btrim(cfg.csc), '') <> ''
),
ids(id_csc) AS (VALUES ('0001'), ('0002'))
SELECT c.etiqueta,
       i.id_csc,
       left(c.valor, 4) AS primeros_4,
       length(c.valor)  AS largo,
       encode(sha256(convert_to(q.base || i.id_csc || c.valor, 'UTF8')), 'hex')
         = q.hash_del_xml AS coincide
  FROM q, cand c, ids i
 ORDER BY coincide DESC, c.etiqueta, i.id_csc;
