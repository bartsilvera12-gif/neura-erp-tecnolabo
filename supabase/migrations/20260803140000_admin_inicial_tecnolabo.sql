-- =============================================================================
-- Usuario administrador inicial de Tecnolabo.
--
-- Enlaza la cuenta ya existente en Supabase Auth con la empresa Tecnolabo.
-- NO crea cuentas de Auth ni contrasenas: la identidad ya existe en auth.users.
--
-- El email y el nombre se leen de auth.users en tiempo de ejecucion a proposito:
-- asi no queda informacion personal versionada en el repositorio.
--
-- Rol `admin` (no `super_admin`): da acceso a todos los modulos activos de la
-- empresa segun resolve-effective-modules, pero NO habilita es_super_admin(),
-- que otorgaria acceso por encima del aislamiento por empresa.
--
-- El email debe coincidir con el de auth.users: empresa_id_actual() y
-- es_super_admin() resuelven la empresa comparando el email del JWT contra
-- tecnolabo.usuarios.email.
--
-- Idempotente: re-ejecutable sin duplicar el usuario.
-- =============================================================================

BEGIN;

INSERT INTO "tecnolabo"."usuarios"
  (empresa_id, auth_user_id, email, nombre, rol, activo, estado)
SELECT
  '2473b6f2-b0c4-4c20-ade7-3cd581a5327b'::uuid,
  u.id,
  lower(trim(u.email)),
  COALESCE(
    NULLIF(trim(u.raw_user_meta_data ->> 'full_name'), ''),
    NULLIF(trim(u.raw_user_meta_data ->> 'name'), ''),
    initcap(split_part(u.email, '@', 1))
  ),
  'admin',
  true,
  'activo'
FROM auth.users u
WHERE u.id = 'c968271d-25ec-454d-909b-3b77cc622c1f'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM "tecnolabo"."usuarios" x
     WHERE x.auth_user_id = 'c968271d-25ec-454d-909b-3b77cc622c1f'::uuid
        OR x.email = lower(trim(u.email))
  );

COMMIT;
