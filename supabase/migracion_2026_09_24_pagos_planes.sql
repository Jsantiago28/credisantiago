-- ==========================================================
-- MIGRACIÓN: pagos de los planes (1, 3 o 12 meses) y WhatsApp
-- ==========================================================
-- Correr en Supabase (SQL Editor). Necesita la migración de planes
-- (migracion_2026_09_23_planes.sql) corrida antes.
-- Se puede correr más de una vez sin problema.
--
-- Qué hace:
--  - profiles.whatsapp: el WhatsApp del prestamista (se pide al
--    registrarse), para recordarle cuando le toca pagar.
--  - Descuentos por pagar varios meses (en ajustes_app, editables desde
--    Administrar): 3 meses con % de descuento y 12 meses con meses gratis.
--  - Tabla pagos_planes: cada mensualidad que recibe el administrador
--    (plan, meses, monto, transferencia / depósito / efectivo, nota, y
--    hasta cuándo quedó el plan). El prestamista ve los suyos.
--  - admin_registrar_pago: guarda el pago y extiende el plan en un solo
--    paso. Solo el administrador puede usarla.

-- 1. WhatsApp del prestamista ---------------------------------------------
alter table profiles add column if not exists whatsapp text;

-- 2. Descuentos por pagar varios meses -------------------------------------
alter table ajustes_app add column if not exists descuento_3_meses int not null default 10;
alter table ajustes_app add column if not exists meses_gratis_12 int not null default 2;

-- 3. Pagos recibidos ------------------------------------------------------
create table if not exists pagos_planes (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  plan text not null references planes(id),
  meses int not null check (meses between 1 and 24),
  monto numeric(12,2) not null check (monto >= 0),
  metodo text not null check (metodo in ('transferencia', 'deposito', 'efectivo')),
  nota text,
  vence_antes date,                    -- hasta cuándo tenía el plan antes de pagar
  vence_despues date not null,         -- hasta cuándo le quedó
  registrado_por uuid default auth.uid(),
  created_at timestamptz default now()
);

create index if not exists idx_pagos_planes_prestamista on pagos_planes(prestamista_id);

alter table pagos_planes enable row level security;

-- El admin ve todos; cada prestamista ve solo los suyos. Se escriben solo
-- con admin_registrar_pago (abajo).
drop policy if exists "pagos_planes_ver" on pagos_planes;
create policy "pagos_planes_ver" on pagos_planes
  for select using (auth.uid() = prestamista_id or public.es_admin());

-- El admin puede borrar un pago mal registrado (no le quita días al plan:
-- eso se corrige con "Cambiar plan").
drop policy if exists "pagos_planes_borrar_admin" on pagos_planes;
create policy "pagos_planes_borrar_admin" on pagos_planes
  for delete using (public.es_admin());

-- 4. Registrar un pago y extender el plan ---------------------------------
-- Si paga el mismo plan que tiene y todavía no ha vencido, los meses se
-- suman desde su vencimiento (no pierde días). Si no, desde hoy.
create or replace function public.admin_registrar_pago(
  prestamista uuid,
  plan_pagado text,
  meses int,
  monto numeric,
  metodo text,
  nota text default null
) returns date
language plpgsql security definer set search_path = public as $$
declare
  actual record;
  desde date;
  nueva date;
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador puede registrar pagos';
  end if;

  select plan, plan_vence into actual from profiles where id = prestamista;
  if not found then
    raise exception 'No existe ese prestamista';
  end if;

  if actual.plan = plan_pagado and actual.plan_vence is not null
     and actual.plan_vence >= current_date then
    desde := actual.plan_vence;
  else
    desde := current_date;
  end if;
  nueva := (desde + make_interval(months => meses))::date;

  update profiles
     set plan = plan_pagado, plan_vence = nueva, aprobado = true
   where id = prestamista;

  insert into pagos_planes
    (prestamista_id, plan, meses, monto, metodo, nota, vence_antes, vence_despues)
  values
    (prestamista, plan_pagado, meses, monto, metodo, nullif(trim(nota), ''),
     actual.plan_vence, nueva);

  return nueva;
end;
$$;

-- 5. El panel del admin trae también el WhatsApp ---------------------------
drop function if exists public.admin_prestamistas();
create or replace function public.admin_prestamistas()
returns table (
  id uuid, nombre text, telefono text, whatsapp text, plan text, plan_vence date,
  aprobado boolean, es_admin boolean, clientes bigint, creado timestamptz
)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.phone, p.whatsapp, p.plan, p.plan_vence, p.aprobado, p.es_admin,
         (select count(*) from clientes c where c.prestamista_id = p.id),
         p.created_at
  from profiles p
  where public.es_admin()
  order by p.aprobado, p.created_at desc
$$;
