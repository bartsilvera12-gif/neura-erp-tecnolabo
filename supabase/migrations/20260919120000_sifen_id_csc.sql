-- =============================================================================
-- SIFEN — ID del CSC (IdCSC) por empresa
-- El SET entrega dos CSC por timbrado: CSC1 (IdCSC 0001) y CSC2 (IdCSC 0002).
-- El `cHashQR` del QR se calcula con el CSC que corresponde al IdCSC enviado en
-- la URL: si se envía IdCSC=0001 y el CSC cargado es el CSC2, el SET rechaza el
-- DE con «El hash del código QR ... es inválido». Por eso el IdCSC debe ser
-- configurable por empresa y no una constante global.
-- =============================================================================

ALTER TABLE public.empresa_sifen_config
  ADD COLUMN IF NOT EXISTS id_csc text NOT NULL DEFAULT '0001';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'empresa_sifen_config_id_csc_chk'
  ) THEN
    ALTER TABLE public.empresa_sifen_config
      ADD CONSTRAINT empresa_sifen_config_id_csc_chk CHECK (id_csc ~ '^[0-9]{4}$');
  END IF;
END $$;

COMMENT ON COLUMN public.empresa_sifen_config.id_csc IS
  'Identificador del CSC asignado por el SET (0001 = CSC1, 0002 = CSC2). Se envía como IdCSC en la URL del QR y debe coincidir con el CSC cargado.';
COMMENT ON COLUMN public.empresa_sifen_config.csc IS
  'Código de Seguridad del Contribuyente correspondiente al id_csc cargado (32 caracteres en producción).';
