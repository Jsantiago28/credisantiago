-- Registro con contraseña y cédula del prestamista (14-10-2026).
--
-- Al registrarse, el prestamista pone su número de cédula y sube la foto de
-- los dos lados. El número va en profiles.contrato_cedula (el mismo que sale
-- en sus contratos) y las fotos en su carpeta privada del bucket. El admin
-- las ve al aprobar la cuenta.
--
-- Correr DESPUÉS de migracion_2026_10_13_contrato.sql y de
-- migracion_2026_10_14_invitaciones.sql.
-- Se puede correr más de una vez sin problema.

-- 1. Fotos de la cédula del prestamista ----------------------------------
alter table profiles add column if not exists cedula_frente_url text;
alter table profiles add column if not exists cedula_reverso_url text;

-- 2. El admin puede ver SOLO las fotos de cédula de los prestamistas -----
-- (no las de los clientes de cada prestamista: esas siguen siendo solo del dueño)
create or replace function public.es_cedula_de_prestamista(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
    where ruta in (p.cedula_frente_url, p.cedula_reverso_url)
  )
$$;

drop policy if exists "fotos_admin_ve_cedula_prestamista" on storage.objects;
create policy "fotos_admin_ve_cedula_prestamista" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'solicitudes-fotos'
    and public.es_admin()
    and public.es_cedula_de_prestamista(name)
  );

-- 3. El panel del admin trae la cédula -----------------------------------
drop function if exists public.admin_prestamistas();
create or replace function public.admin_prestamistas()
returns table (
  id uuid, nombre text, telefono text, whatsapp text, plan text, plan_vence date,
  aprobado boolean, es_admin boolean, clientes bigint, creado timestamptz,
  invitado_por uuid, invitado_por_nombre text, premio_invitacion date, ya_pago boolean,
  cedula text, cedula_frente_url text, cedula_reverso_url text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.phone, p.whatsapp, p.plan, p.plan_vence, p.aprobado, p.es_admin,
         (select count(*) from clientes c where c.prestamista_id = p.id),
         p.created_at,
         p.invitado_por,
         (select coalesce(nullif(trim(i.negocio), ''), i.nombre) from profiles i
           where i.id = p.invitado_por),
         p.premio_invitacion,
         exists (select 1 from pagos_planes pp where pp.prestamista_id = p.id and pp.monto > 0),
         p.contrato_cedula, p.cedula_frente_url, p.cedula_reverso_url
  from profiles p
  where public.es_admin()
  order by p.aprobado, p.created_at desc
$$;
