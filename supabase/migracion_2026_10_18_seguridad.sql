-- Seguridad, fotos para el cobrador y aviso de versión nueva (18-10-2026).
--
--  1. Link de solicitudes: freno contra el relleno de solicitudes falsas.
--     Como mucho 30 solicitudes por hora para cada prestamista y 3 por día
--     con la misma cédula. Toda solicitud llega como "nueva" (nadie de
--     afuera la puede mandar ya aprobada).
--  2. Si al jefe se le vence el plan (pasa a Gratis, sin cobradores), sus
--     cobradores dejan de ver clientes y de cobrar hasta que renueve. Si el
--     plan baja (ej. de 3 a 1 cobrador), sigue el más antiguo.
--  3. El cobrador ve la foto de la CARA de los clientes de su ruta (no la
--     cédula ni las evidencias), para reconocerlos en la calle.
--  4. Las funciones del límite del plan ya no las puede consultar alguien
--     sin cuenta.
--  5. El APK avisa cuando hay una versión nueva para bajar.
--
-- Correr DESPUÉS de migracion_2026_10_18_saldar_antes.sql.
-- Se puede correr más de una vez sin problema.

-- 1. Freno a solicitudes falsas ----------------------------------------------
create or replace function public.frenar_solicitudes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- El prestamista o el admin cargando una a mano: sin freno.
  if auth.uid() is not null and (auth.uid() = new.prestamista_id or public.es_admin()) then
    return new;
  end if;
  new.estado := 'nueva';
  if (select count(*) from solicitudes
       where prestamista_id = new.prestamista_id
         and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'DEMASIADAS_SOLICITUDES: intenta de nuevo más tarde';
  end if;
  if new.cedula is not null and (select count(*) from solicitudes
       where prestamista_id = new.prestamista_id
         and cedula = new.cedula
         and created_at > now() - interval '1 day') >= 3 then
    raise exception 'DEMASIADAS_SOLICITUDES: ya enviaste esta solicitud hoy';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_frenar_solicitudes on solicitudes;
create trigger trg_frenar_solicitudes
  before insert on solicitudes
  for each row execute function public.frenar_solicitudes();

create index if not exists idx_solicitudes_prestamista_fecha
  on solicitudes (prestamista_id, created_at desc);

-- 2. Cobradores dentro del plan del jefe --------------------------------------
-- true si el cobrador está activo y cabe en el plan de su jefe (los más
-- antiguos primero).
create or replace function public.cobrador_vigente(cobrador uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from cobradores c
    where c.id = cobrador and c.activo
      and (select count(*) from cobradores o
            where o.prestamista_id = c.prestamista_id and o.activo
              and (o.created_at, o.id) < (c.created_at, c.id))
          < coalesce(public.limite_cobradores(c.prestamista_id), 0)
  )
$$;

create or replace function public.mi_cobrador() returns uuid
language sql stable security definer set search_path = public as $$
  select id from cobradores
   where user_id = auth.uid() and activo and public.cobrador_vigente(id)
   limit 1
$$;

create or replace function public.cobrador_jefe() returns uuid
language sql stable security definer set search_path = public as $$
  select prestamista_id from cobradores
   where user_id = auth.uid() and activo and public.cobrador_vigente(id)
   limit 1
$$;

create or replace function public.mi_jefe()
returns table (
  cobrador_id uuid, cobrador_nombre text,
  prestamista_id uuid, nombre text, negocio text, whatsapp text, phone text,
  recibo_logo text, recibo_telefono text, recibo_direccion text, recibo_mensaje text
)
language sql stable security definer set search_path = public as $$
  select c.id, c.nombre,
         p.id, p.nombre, p.negocio, p.whatsapp, p.phone,
         p.recibo_logo, p.recibo_telefono, p.recibo_direccion, p.recibo_mensaje
    from cobradores c join profiles p on p.id = c.prestamista_id
   where c.user_id = auth.uid() and c.activo and public.cobrador_vigente(c.id)
   limit 1
$$;

-- Para la app: si quien entra es cobrador pero el plan de su jefe no lo
-- cubre, el nombre del negocio del jefe (para avisarle); si no, null.
create or replace function public.cobrador_sin_plan() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(p.negocio), ''), p.nombre)
    from cobradores c join profiles p on p.id = c.prestamista_id
   where c.user_id = auth.uid() and c.activo and not public.cobrador_vigente(c.id)
   limit 1
$$;

revoke all on function public.cobrador_sin_plan() from public;
grant execute on function public.cobrador_sin_plan() to authenticated;

-- 3. El cobrador ve la cara de los clientes de su ruta -----------------------
create or replace function public.es_cara_de_mi_ruta(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from clientes c
    where c.cobrador_id is not null
      and c.cobrador_id = public.mi_cobrador()
      and c.foto_cara_url = ruta
  )
$$;

drop policy if exists "fotos_cara_para_cobrador" on storage.objects;
create policy "fotos_cara_para_cobrador" on storage.objects
  for select to authenticated
  using (bucket_id = 'solicitudes-fotos' and public.es_cara_de_mi_ruta(name));

-- 4. Funciones del plan: solo para quien tiene cuenta -------------------------
revoke all on function public.limite_clientes(uuid) from public, anon;
grant execute on function public.limite_clientes(uuid) to authenticated;
revoke all on function public.limite_cobradores(uuid) from public, anon;
grant execute on function public.limite_cobradores(uuid) to authenticated;
revoke all on function public.cobrador_vigente(uuid) from public, anon;
grant execute on function public.cobrador_vigente(uuid) to authenticated;

-- 5. Aviso de versión nueva del APK -------------------------------------------
-- El admin pone en Admin → Ajustes la última versión y el enlace para
-- bajarla (Drive); el APK viejo avisa al abrir.
alter table ajustes_app add column if not exists apk_version text;
alter table ajustes_app add column if not exists apk_enlace text;
