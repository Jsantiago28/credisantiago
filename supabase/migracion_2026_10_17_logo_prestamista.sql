-- Logo del prestamista en su formulario de solicitudes (17-10-2026).
--
-- El prestamista sube su logo en Perfil → "Personalizar mi recibo y
-- contrato". Ya salía en sus recibos; ahora también en su app y en el
-- formulario /s/{slug} que llenan sus clientes. El link para invitar a
-- otros prestamistas (/i/...) sigue con el logo de CrediSantiago.
--
-- El formulario lo abre un cliente SIN sesión, así que:
--   1. prestamista_del_link también entrega dónde está el logo;
--   2. cualquiera puede ver un archivo SOLO si es el logo de algún
--      prestamista. Las fotos de cédulas, caras y evidencias siguen privadas.
--
-- Correr DESPUÉS de migracion_2026_10_13_link_publico.sql.
-- Se puede correr más de una vez sin problema.

-- 1. El link trae el logo --------------------------------------------------
drop function if exists public.prestamista_del_link(text);
create or replace function public.prestamista_del_link(p_slug text)
returns table (id uuid, nombre text, negocio text, phone text, exigir_evidencias boolean,
               logo text)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.negocio,
         coalesce(nullif(trim(p.recibo_telefono), ''),
                  nullif(trim(p.whatsapp), ''),
                  nullif(trim(p.phone), '')),
         p.exigir_evidencias,
         nullif(trim(p.recibo_logo), '')
  from profiles p
  where p.slug = p_slug
  limit 1
$$;

revoke all on function public.prestamista_del_link(text) from public;
grant execute on function public.prestamista_del_link(text) to anon, authenticated;

-- 2. Los logos se pueden ver sin sesión (y nada más) ----------------------
create or replace function public.es_logo_de_prestamista(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles p where p.recibo_logo = ruta)
$$;

drop policy if exists "fotos_logo_publico" on storage.objects;
create policy "fotos_logo_publico" on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'solicitudes-fotos'
    and public.es_logo_de_prestamista(name)
  );

-- Revisa: debe salir tu negocio y, si ya subiste logo, dónde está.
select * from public.prestamista_del_link('perez-soluciones');
