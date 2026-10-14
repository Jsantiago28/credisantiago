-- Link de solicitudes (13-10-2026): el formulario /s/{slug} lo abre un
-- cliente SIN sesión. Las reglas de `profiles` (con razón) no le dejan leer
-- ningún perfil, así que el formulario no encontraba al prestamista y decía
-- "Este link no es válido" (solo funcionaba en el teléfono del propio
-- prestamista, que tenía la sesión abierta).
--
-- Esta función le da al formulario SOLO lo que necesita del prestamista de
-- ese link: id, nombre, negocio, teléfono (para el botón de WhatsApp) y si
-- exige evidencia de ingresos. El resto del perfil (plan, correo, recibo...)
-- sigue privado.
--
-- Se puede correr más de una vez.

create or replace function public.prestamista_del_link(p_slug text)
returns table (id uuid, nombre text, negocio text, phone text, exigir_evidencias boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.negocio, p.phone, p.exigir_evidencias
  from profiles p
  where p.slug = p_slug
  limit 1
$$;

revoke all on function public.prestamista_del_link(text) from public;
grant execute on function public.prestamista_del_link(text) to anon, authenticated;

-- Revisa: debe salir tu negocio (cambia el slug por el tuyo).
select * from public.prestamista_del_link('perez-soluciones');
