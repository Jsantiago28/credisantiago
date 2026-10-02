-- ==========================================================
-- MIGRACIÓN: registro con aprobación + planes (suscripción)
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de usar la versión de la app con
-- planes. Se puede correr más de una vez sin problema.
--
-- ⚠️ Antes de correrla, revisa la línea marcada "TU CORREO" (sección 7):
--    ahí se te marca como administrador.
--
-- Qué hace:
--  - Tabla `planes`: nombre, precio y cuántos clientes permite cada plan.
--    Se puede editar en Table Editor sin tocar la app.
--  - Tabla `ajustes_app`: tu WhatsApp de soporte, cómo te pagan y si las
--    cuentas nuevas necesitan tu aprobación.
--  - En profiles: plan, fecha en que vence, si está aprobado y si es admin.
--  - Reglas que NO se pueden saltar desde la app:
--      * nadie puede ponerse un plan, aprobarse ni hacerse admin solo;
--      * no se pueden crear más clientes que los del plan (el plan vencido
--        cuenta como Gratis; una cuenta sin aprobar no puede crear clientes).
--  - Función para el panel de administración (solo admins).

-- 1. Planes -------------------------------------------------------------
create table if not exists planes (
  id text primary key,                 -- gratis / basico / pro / premium
  nombre text not null,
  precio_mensual numeric(12,2) not null default 0,
  max_clientes int,                    -- null = sin límite
  orden int not null default 0
);

insert into planes (id, nombre, precio_mensual, max_clientes, orden) values
  ('gratis',  'Gratis',  0,    5,    0),
  ('basico',  'Básico',  790,  30,   1),
  ('pro',     'Pro',     1490, 100,  2),
  ('premium', 'Premium', 2490, null, 3)
on conflict (id) do nothing;          -- si ya existen, no pisa tus cambios

alter table planes enable row level security;
drop policy if exists "planes_leer" on planes;
create policy "planes_leer" on planes for select to authenticated using (true);

-- 2. Ajustes de la app (una sola fila) -----------------------------------
create table if not exists ajustes_app (
  id int primary key default 1 check (id = 1),
  whatsapp_soporte text,               -- ej. 809-555-1234
  instrucciones_pago text,             -- ej. Banreservas cuenta 123... a nombre de...
  registro_requiere_aprobacion boolean not null default true
);
insert into ajustes_app (id) values (1) on conflict (id) do nothing;

alter table ajustes_app enable row level security;
drop policy if exists "ajustes_leer" on ajustes_app;
create policy "ajustes_leer" on ajustes_app for select to authenticated using (true);

-- 3. Columnas nuevas en profiles -----------------------------------------
alter table profiles add column if not exists plan text not null default 'gratis' references planes(id);
alter table profiles add column if not exists plan_vence date;       -- null = no vence (gratis)
alter table profiles add column if not exists aprobado boolean not null default false;
alter table profiles add column if not exists es_admin boolean not null default false;

-- Las cuentas que ya existían quedan aprobadas (nadie se queda fuera).
-- Solo la primera vez: después, cada cuenta nueva la apruebas tú.
do $$
begin
  if not exists (select 1 from profiles where aprobado) then
    update profiles set aprobado = true;
  end if;
end $$;

-- 4. ¿Quién es admin? (security definer: lee sin restricciones) ----------
create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select es_admin from profiles where id = auth.uid()), false)
$$;

-- El admin edita los ajustes (WhatsApp de soporte, cómo pagar...).
drop policy if exists "ajustes_admin" on ajustes_app;
create policy "ajustes_admin" on ajustes_app for update using (public.es_admin());

-- Los admins ven y actualizan todos los perfiles (para aprobar y dar planes).
drop policy if exists "profiles_admin_select" on profiles;
create policy "profiles_admin_select" on profiles for select using (public.es_admin());
drop policy if exists "profiles_admin_update" on profiles;
create policy "profiles_admin_update" on profiles for update using (public.es_admin());

-- 5. Nadie se pone plan, se aprueba ni se hace admin solo -----------------
create or replace function public.proteger_plan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Sin usuario de la app (SQL Editor de Supabase) o admin: se permite.
  if auth.uid() is null or public.es_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.plan := 'gratis';
    new.plan_vence := null;
    new.es_admin := false;
    new.aprobado := not coalesce(
      (select registro_requiere_aprobacion from ajustes_app where id = 1), true);
  elsif new.plan is distinct from old.plan
     or new.plan_vence is distinct from old.plan_vence
     or new.aprobado is distinct from old.aprobado
     or new.es_admin is distinct from old.es_admin then
    raise exception 'Solo el administrador puede cambiar el plan o la aprobación';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_plan on profiles;
create trigger trg_proteger_plan
  before insert or update on profiles
  for each row execute function public.proteger_plan();

-- 6. Límite de clientes según el plan ------------------------------------
create or replace function public.limite_clientes(prestamista uuid) returns int
language sql stable security definer set search_path = public as $$
  select case
    when not p.aprobado then 0
    else coalesce(
      (select pl.max_clientes from planes pl
        where pl.id = case when p.plan_vence is not null and p.plan_vence < current_date
                           then 'gratis' else p.plan end),
      2147483647)                       -- plan sin límite
  end
  from profiles p where p.id = prestamista
$$;

create or replace function public.validar_limite_clientes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  limite int := coalesce(public.limite_clientes(new.prestamista_id), 0);
  actuales int;
begin
  select count(*) into actuales from clientes where prestamista_id = new.prestamista_id;
  if actuales >= limite then
    raise exception 'LIMITE_PLAN: tu plan permite % clientes', limite;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_limite_clientes on clientes;
create trigger trg_limite_clientes
  before insert on clientes
  for each row execute function public.validar_limite_clientes();

-- Panel de administración: todos los prestamistas con su plan y clientes.
create or replace function public.admin_prestamistas()
returns table (
  id uuid, nombre text, telefono text, plan text, plan_vence date,
  aprobado boolean, es_admin boolean, clientes bigint, creado timestamptz
)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.phone, p.plan, p.plan_vence, p.aprobado, p.es_admin,
         (select count(*) from clientes c where c.prestamista_id = p.id),
         p.created_at
  from profiles p
  where public.es_admin()
  order by p.aprobado, p.created_at desc
$$;

-- 7. TU CORREO: te marca como administrador ------------------------------
-- Cambia el correo si entras a la app con otro. Como dueño de la app
-- quedas en Premium sin vencimiento (sin límite de clientes).
update profiles set es_admin = true, aprobado = true, plan = 'premium', plan_vence = null
where id in (select id from auth.users where email = 'applej904@gmail.com');

-- Revisa que quedaste como admin (debe salir tu nombre con es_admin = true
-- y plan = premium). Si no sale ninguna fila, el correo no coincide:
select nombre, plan, aprobado, es_admin from profiles where es_admin;
