-- ============================================================
-- Verificación en dos pasos (opcional, en Perfil)
-- ============================================================
-- Quien la activa entra con su contraseña Y un código de 6 números de una
-- app de códigos (Google Authenticator, Microsoft Authenticator...).
--
-- La app pide el código, pero eso solo no basta: con la contraseña robada
-- se podría leer la base de datos directo. Por eso aquí, a quien tiene los
-- dos pasos activados y todavía no puso el código (sesión "aal1"), la base
-- de datos no le muestra ni le deja cambiar nada. A quien no los activó no
-- le cambia nada.
--
-- OJO: a cada tabla nueva con RLS hay que ponerle la regla "dos_pasos"
-- (volver a correr el paso 2). Las pruebas de la base de datos avisan si
-- a alguna le falta.
-- Se puede correr más de una vez.

-- 1. ¿Puede seguir? -------------------------------------------------------------
create or replace function public.dos_pasos_ok() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
      or not exists (select 1 from auth.mfa_factors f
                      where f.user_id = auth.uid() and f.status = 'verified');
$$;
revoke all on function public.dos_pasos_ok() from public;
grant execute on function public.dos_pasos_ok() to anon, authenticated;

-- 2. La regla en cada tabla con RLS (restrictiva: se suma a las que ya hay) ----
do $$
declare
  t record;
begin
  for t in
    select c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
  loop
    execute format('drop policy if exists dos_pasos on public.%I', t.relname);
    execute format(
      'create policy dos_pasos on public.%I as restrictive for all to authenticated '
      'using ((select public.dos_pasos_ok())) with check ((select public.dos_pasos_ok()))',
      t.relname);
  end loop;
end $$;

-- Las fotos (cédulas, caras, logos) también.
drop policy if exists dos_pasos on storage.objects;
create policy dos_pasos on storage.objects as restrictive for all to authenticated
  using ((select public.dos_pasos_ok())) with check ((select public.dos_pasos_ok()));

-- 3. Perdió el teléfono: el admin le quita los dos pasos ------------------------
create or replace function public.quitar_dos_pasos(usuario uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador puede quitar la verificación en dos pasos';
  end if;
  delete from auth.mfa_factors where user_id = usuario;
end;
$$;
revoke all on function public.quitar_dos_pasos(uuid) from public, anon;
grant execute on function public.quitar_dos_pasos(uuid) to authenticated;
