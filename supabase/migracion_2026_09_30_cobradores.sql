-- ==========================================================
-- MIGRACIÓN: cobradores (30-09-2026)
-- ==========================================================
-- El prestamista invita cobradores por correo (Perfil → Mis cobradores) y
-- les reparte los clientes. El cobrador entra a la misma app con su correo
-- y el código, y solo ve y cobra a SUS clientes:
--
--   * ve sus clientes (sin fotos), sus préstamos, cobros y gestiones;
--   * cobra (el cobro queda a nombre del jefe, con su número de recibo, y
--     marcado con el cobrador que lo hizo);
--   * anota gestiones y promesas de pago;
--   * puede marcar la ubicación de la casa del cliente;
--   * NO ve otros clientes, reportes, ganancias ni solicitudes; NO presta,
--     NO cancela préstamos, NO anula cobros, NO cambia datos del cliente.
--
-- Todo esto lo aplica la base de datos (reglas y triggers), no la app.
-- Cuántos cobradores puede tener cada plan: planes.max_cobradores.
--
-- Se puede correr más de una vez sin problema.

-- 1. Cobradores por plan ------------------------------------------------
alter table planes add column if not exists max_cobradores int default 0;  -- null = sin límite
update planes set max_cobradores = 0    where id = 'gratis';
update planes set max_cobradores = 1    where id = 'basico';
update planes set max_cobradores = 3    where id = 'pro';
update planes set max_cobradores = null where id = 'premium';

-- 2. Tabla de cobradores ------------------------------------------------
create table if not exists cobradores (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  nombre text not null,
  email text not null,                 -- con este correo entra a la app
  telefono text,
  user_id uuid references auth.users(id) on delete set null,  -- se llena cuando entra por primera vez
  activo boolean not null default true,
  created_at timestamptz default now()
);

-- Un correo solo puede ser cobrador activo de un prestamista a la vez.
create unique index if not exists cobradores_email_activo
  on cobradores (email) where activo;
create unique index if not exists cobradores_usuario_activo
  on cobradores (user_id) where activo and user_id is not null;
create index if not exists idx_cobradores_prestamista on cobradores (prestamista_id);

-- A qué cobrador le toca cada cliente, y quién hizo cada cobro. Van aquí,
-- antes de las funciones que las usan.
alter table clientes add column if not exists cobrador_id uuid references cobradores(id) on delete set null;
create index if not exists idx_clientes_cobrador on clientes (cobrador_id);
alter table pagos add column if not exists cobrador_id uuid references cobradores(id) on delete set null;
create index if not exists idx_pagos_cobrador on pagos (cobrador_id);

alter table cobradores enable row level security;

drop policy if exists "cobradores_dueno" on cobradores;
create policy "cobradores_dueno" on cobradores
  for all using (auth.uid() = prestamista_id) with check (auth.uid() = prestamista_id);

drop policy if exists "cobradores_se_ve" on cobradores;
create policy "cobradores_se_ve" on cobradores
  for select using (auth.uid() = user_id);

-- 3. Funciones de ayuda (security definer: consultan sin las reglas, pero
--    solo devuelven datos del que pregunta) --------------------------------

-- El registro de cobrador (activo) del que está usando la app, o null.
create or replace function public.mi_cobrador() returns uuid
language sql stable security definer set search_path = public as $$
  select id from cobradores where user_id = auth.uid() and activo limit 1
$$;

-- El prestamista para el que cobra el que está usando la app, o null.
create or replace function public.cobrador_jefe() returns uuid
language sql stable security definer set search_path = public as $$
  select prestamista_id from cobradores where user_id = auth.uid() and activo limit 1
$$;

-- ¿Este cliente está en la ruta del cobrador que pregunta?
create or replace function public.es_cliente_de_mi_ruta(cliente uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from clientes c
    where c.id = cliente
      and c.cobrador_id is not null
      and c.cobrador_id = public.mi_cobrador()
  )
$$;

-- ¿Este préstamo es de un cliente de la ruta del cobrador que pregunta?
create or replace function public.es_prestamo_de_mi_ruta(prestamo uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from prestamos p
    where p.id = prestamo and public.es_cliente_de_mi_ruta(p.cliente_id)
  )
$$;

-- 4. Límite de cobradores según el plan ----------------------------------
create or replace function public.limite_cobradores(prestamista uuid) returns int
language sql stable security definer set search_path = public as $$
  select case
    when not p.aprobado then 0
    else coalesce(
      (select pl.max_cobradores from planes pl
        where pl.id = case when p.plan_vence is not null and p.plan_vence < current_date
                           then 'gratis' else p.plan end),
      2147483647)                       -- plan sin límite
  end
  from profiles p where p.id = prestamista
$$;

-- Al agregar (o volver a activar) un cobrador: correo en minúsculas, sin
-- usuario amarrado a mano, y dentro del límite del plan.
create or replace function public.validar_cobrador() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  limite int;
  activos int;
  se_activa boolean;
begin
  new.email := lower(trim(new.email));
  new.nombre := trim(new.nombre);

  if tg_op = 'INSERT' then
    se_activa := new.activo;
    -- El usuario lo amarra aceptar_invitacion_cobrador(), nunca el prestamista.
    if auth.uid() is not null then new.user_id := null; end if;
  else
    se_activa := new.activo and not old.activo;
    if new.email is distinct from old.email then
      new.user_id := null;              -- otro correo: otra persona
    elsif new.user_id is distinct from old.user_id
          and auth.uid() is not null
          and coalesce(current_setting('app.aceptando_cobrador', true), '') <> 'si' then
      raise exception 'El usuario del cobrador no se puede cambiar a mano';
    end if;
    if new.prestamista_id is distinct from old.prestamista_id then
      raise exception 'Un cobrador no se puede pasar a otro prestamista';
    end if;
  end if;

  -- Límite del plan (el SQL Editor de Supabase no tiene límite).
  if auth.uid() is not null and se_activa then
    limite := coalesce(public.limite_cobradores(new.prestamista_id), 0);
    select count(*) into activos from cobradores
     where prestamista_id = new.prestamista_id and activo and id <> new.id;
    if activos >= limite then
      raise exception 'LIMITE_COBRADORES: tu plan permite % cobrador(es)', limite;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_cobrador on cobradores;
create trigger trg_validar_cobrador
  before insert or update on cobradores
  for each row execute function public.validar_cobrador();

-- 5. El cobrador entra por primera vez: se amarra su usuario -------------
-- Devuelve el id del registro de cobrador, o null si ese correo no fue
-- invitado (o si ya es prestamista: una cuenta no puede ser las dos cosas).
create or replace function public.aceptar_invitacion_cobrador() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  correo text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  registro uuid;
begin
  if auth.uid() is null or correo = '' then return null; end if;
  if exists (select 1 from profiles where id = auth.uid()) then return null; end if;

  select id into registro from cobradores
   where email = correo and activo and (user_id is null or user_id = auth.uid())
   limit 1;
  if registro is null then return null; end if;

  perform set_config('app.aceptando_cobrador', 'si', true);
  update cobradores set user_id = auth.uid() where id = registro and user_id is null;
  return registro;
end;
$$;

-- Datos del cobrador y de su jefe (para la app del cobrador: el nombre del
-- negocio y lo que va en el recibo). Vacío si no es cobrador activo.
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
   where c.user_id = auth.uid() and c.activo
   limit 1
$$;

-- 6. Clientes: a qué cobrador le toca cada uno ----------------------------
-- (la columna clientes.cobrador_id se agrega en el paso 2)

-- El cobrador asignado tiene que ser del mismo prestamista. Y un cobrador
-- solo puede cambiar la ubicación (lat/lng) de sus clientes, nada más.
create or replace function public.proteger_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cambia_cobrador boolean;
begin
  if tg_op = 'INSERT' then
    cambia_cobrador := new.cobrador_id is not null;
  else
    cambia_cobrador := new.cobrador_id is not null
                       and new.cobrador_id is distinct from old.cobrador_id;
  end if;
  if cambia_cobrador
     and not exists (select 1 from cobradores
                      where id = new.cobrador_id and prestamista_id = new.prestamista_id) then
    raise exception 'Ese cobrador no es tuyo';
  end if;

  if tg_op = 'UPDATE' then
    if auth.uid() is not null and auth.uid() is distinct from old.prestamista_id
       and not public.es_admin()
       and (to_jsonb(new) - 'lat' - 'lng') is distinct from (to_jsonb(old) - 'lat' - 'lng') then
      raise exception 'El cobrador solo puede marcar la ubicación del cliente';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_cliente on clientes;
create trigger trg_proteger_cliente
  before insert or update on clientes
  for each row execute function public.proteger_cliente();

drop policy if exists "clientes_cobrador_ver" on clientes;
create policy "clientes_cobrador_ver" on clientes
  for select using (cobrador_id is not null and cobrador_id = public.mi_cobrador());

drop policy if exists "clientes_cobrador_ubicacion" on clientes;
create policy "clientes_cobrador_ubicacion" on clientes
  for update using (cobrador_id is not null and cobrador_id = public.mi_cobrador())
  with check (cobrador_id = public.mi_cobrador());

-- 7. Préstamos: el cobrador ve los de su ruta y, al cobrar, solo mueve la
--    próxima fecha y lo marca saldado (o de vuelta en la calle) -----------
create or replace function public.proteger_prestamo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and auth.uid() is distinct from old.prestamista_id
     and not public.es_admin() then
    if (to_jsonb(new) - 'proximo_pago' - 'estado') is distinct from
       (to_jsonb(old) - 'proximo_pago' - 'estado') then
      raise exception 'El cobrador no puede cambiar el préstamo';
    end if;
    if new.estado is distinct from old.estado
       and not (old.estado in ('en_calle', 'pagado') and new.estado in ('en_calle', 'pagado')) then
      raise exception 'El cobrador no puede cambiar el préstamo';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_prestamo on prestamos;
create trigger trg_proteger_prestamo
  before update on prestamos
  for each row execute function public.proteger_prestamo();

drop policy if exists "prestamos_cobrador_ver" on prestamos;
create policy "prestamos_cobrador_ver" on prestamos
  for select using (public.es_cliente_de_mi_ruta(cliente_id));

drop policy if exists "prestamos_cobrador_cobrar" on prestamos;
create policy "prestamos_cobrador_cobrar" on prestamos
  for update using (public.es_cliente_de_mi_ruta(cliente_id))
  with check (public.es_cliente_de_mi_ruta(cliente_id));

-- 8. Cobros: quién lo cobró; el cobrador cobra pero no anula --------------
-- (la columna pagos.cobrador_id se agrega en el paso 2)

-- El cobrador lo pone la base de datos (nadie puede poner a otro).
create or replace function public.marcar_cobrador_del_pago() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.cobrador_id := public.mi_cobrador();
  return new;
end;
$$;

drop trigger if exists trg_cobrador_del_pago on pagos;
create trigger trg_cobrador_del_pago
  before insert on pagos
  for each row execute function public.marcar_cobrador_del_pago();

-- El número de recibo se calcula sin las reglas: el cobrador no ve todos
-- los cobros del jefe y, si no, repetiría números.
create or replace function asignar_numero_recibo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.numero_recibo is null then
    -- Un cobro a la vez por prestamista mientras se calcula el siguiente número.
    perform pg_advisory_xact_lock(hashtext('recibo:' || new.prestamista_id::text));
    select coalesce(max(numero_recibo), 0) + 1
      into new.numero_recibo
      from pagos
     where prestamista_id = new.prestamista_id;
  end if;
  return new;
end;
$$;

drop policy if exists "pagos_cobrador_ver" on pagos;
create policy "pagos_cobrador_ver" on pagos
  for select using (public.es_prestamo_de_mi_ruta(prestamo_id));

drop policy if exists "pagos_cobrador_cobrar" on pagos;
create policy "pagos_cobrador_cobrar" on pagos
  for insert with check (
    prestamista_id = public.cobrador_jefe()
    and public.es_prestamo_de_mi_ruta(prestamo_id)
    and not anulado
  );

-- 9. Gestiones: el cobrador ve y anota las de su ruta ---------------------
drop policy if exists "gestiones_cobrador_ver" on gestiones;
create policy "gestiones_cobrador_ver" on gestiones
  for select using (public.es_prestamo_de_mi_ruta(prestamo_id));

drop policy if exists "gestiones_cobrador_anotar" on gestiones;
create policy "gestiones_cobrador_anotar" on gestiones
  for insert with check (
    prestamista_id = public.cobrador_jefe()
    and public.es_prestamo_de_mi_ruta(prestamo_id)
    and hecho_por = auth.uid()
  );

-- 10. El cobrador puede bajar el logo del jefe (para el recibo) ----------
create or replace function public.es_logo_de_mi_jefe(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
    where p.id = public.cobrador_jefe() and p.recibo_logo = ruta
  )
$$;

drop policy if exists "fotos_logo_para_cobrador" on storage.objects;
create policy "fotos_logo_para_cobrador" on storage.objects
  for select to authenticated
  using (bucket_id = 'solicitudes-fotos' and public.es_logo_de_mi_jefe(name));

-- 11. Tiempo real: que Inicio del cobrador se entere de los cambios -------
-- (prestamos y pagos ya están en supabase_realtime; las reglas de arriba
-- deciden qué le llega a cada quien).
