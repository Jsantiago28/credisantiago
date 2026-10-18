-- Términos, privacidad y "Borrar mi cuenta" (18-10-2026).
--
--  * Se anota cuándo el prestamista aceptó los Términos y la Política de
--    privacidad (al registrarse) y cuándo el cliente autorizó el uso de sus
--    datos (al enviar la solicitud). Ley 172-13 de datos personales.
--  * Cada usuario puede borrar su cuenta desde la app (lo exige Google Play
--    y la ley): se borra su usuario y, en cadena, su perfil, clientes,
--    préstamos, cobros, gastos, cobradores, solicitudes, etc. La app antes
--    borra sus fotos de la carpeta privada.
--
-- Correr DESPUÉS de migracion_2026_10_14_invitaciones.sql.
-- Se puede correr más de una vez sin problema.

-- 1. Cuándo se aceptaron los términos ---------------------------------------
alter table profiles add column if not exists acepto_terminos_en timestamptz;
alter table solicitudes add column if not exists acepto_privacidad_en timestamptz;

-- 2. Cada prestamista puede borrar los archivos de SU carpeta --------------
drop policy if exists "fotos_borrar_propias" on storage.objects;
create policy "fotos_borrar_propias" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'solicitudes-fotos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 3. Al borrar a quien invitó, a sus invitados se les quita el "invitado
--    por" (on delete set null): eso sí se permite. Lo demás sigue igual.
create or replace function public.proteger_invitacion() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.es_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.invitado_por = new.id then
      new.invitado_por := null;
    end if;
    new.premio_invitacion := null;
  elsif (new.invitado_por is distinct from old.invitado_por
         and not (new.invitado_por is null and old.invitado_por = auth.uid()))
     or new.premio_invitacion is distinct from old.premio_invitacion then
    raise exception 'Solo el administrador puede cambiar la invitación';
  end if;
  return new;
end;
$$;

-- 4. Borrar mi cuenta ---------------------------------------------------------
create or replace function public.borrar_mi_cuenta() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then
    raise exception 'Hay que entrar para borrar la cuenta';
  end if;
  if exists (select 1 from public.profiles where id = auth.uid() and es_admin) then
    raise exception 'La cuenta del administrador no se borra desde la app';
  end if;
  -- En cadena se borra todo lo del prestamista (o se suelta al cobrador).
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.borrar_mi_cuenta() from public;
grant execute on function public.borrar_mi_cuenta() to authenticated;
