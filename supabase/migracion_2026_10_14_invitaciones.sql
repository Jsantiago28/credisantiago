-- Invitaciones entre prestamistas (14-10-2026).
--
-- Cada prestamista tiene su link para invitar: /i/{su-slug}. Quien se
-- registra con ese link queda marcado como "invitado por" él. Cuando el
-- invitado paga su primer plan, el admin le da al que invitó 1 MES GRATIS
-- de su plan (con un botón en el panel de administración).
--
-- Reglas que la app no se puede saltar:
--   * "invitado por" solo se pone al crear el perfil, y nadie se invita a sí mismo;
--   * el premio solo lo da el admin, una sola vez por invitado, y solo si el
--     invitado ya pagó un plan (un pago con monto mayor que 0).
--
-- Correr DESPUÉS de migracion_2026_09_24_pagos_planes.sql.
-- Se puede correr más de una vez sin problema.

-- 1. Quién invitó a quién, y cuándo se dio el premio ---------------------
alter table profiles add column if not exists invitado_por uuid
  references profiles(id) on delete set null;
alter table profiles add column if not exists premio_invitacion date;  -- null = premio pendiente

-- 2. Nadie se cambia el "invitado por" ni se da el premio solo ------------
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
  elsif new.invitado_por is distinct from old.invitado_por
     or new.premio_invitacion is distinct from old.premio_invitacion then
    raise exception 'Solo el administrador puede cambiar la invitación';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_invitacion on profiles;
create trigger trg_proteger_invitacion
  before insert or update on profiles
  for each row execute function public.proteger_invitacion();

-- 3. El premio aparece en los pagos como "premio" -------------------------
alter table pagos_planes drop constraint if exists pagos_planes_metodo_check;
alter table pagos_planes add constraint pagos_planes_metodo_check
  check (metodo in ('transferencia', 'deposito', 'efectivo', 'premio'));

-- 4. Dar el premio: 1 mes gratis al que invitó ----------------------------
-- Si el que invitó tiene un plan pagado y vigente, se le alarga 1 mes ese
-- plan; si está en Gratis (o se le venció), recibe 1 mes de Básico.
create or replace function public.admin_premio_invitacion(invitado uuid)
returns date
language plpgsql security definer set search_path = public as $$
declare
  quien_invito uuid;
  ya_premiado date;
  nombre_invitado text;
  su_plan text;
  su_vence date;
  nueva date;
begin
  if not public.es_admin() then
    raise exception 'Solo el administrador puede dar el premio';
  end if;

  select invitado_por, premio_invitacion, nombre
    into quien_invito, ya_premiado, nombre_invitado
    from profiles where id = invitado;
  if quien_invito is null then
    raise exception 'Este prestamista no vino invitado por nadie';
  end if;
  if ya_premiado is not null then
    raise exception 'El premio por este invitado ya se dio el %', ya_premiado;
  end if;
  if not exists (select 1 from pagos_planes
                  where prestamista_id = invitado and monto > 0) then
    raise exception 'El invitado todavía no ha pagado ningún plan';
  end if;

  select plan, plan_vence into su_plan, su_vence from profiles where id = quien_invito;
  if su_plan = 'gratis' or su_vence is null or su_vence < current_date then
    su_plan := 'basico';
  end if;

  nueva := public.admin_registrar_pago(
    quien_invito, su_plan, 1, 0, 'premio',
    'Premio por invitar a ' || coalesce(nombre_invitado, 'un prestamista'));

  update profiles set premio_invitacion = current_date where id = invitado;
  return nueva;
end;
$$;

-- 5. El panel del admin trae quién invitó y si toca dar premio -----------
drop function if exists public.admin_prestamistas();
create or replace function public.admin_prestamistas()
returns table (
  id uuid, nombre text, telefono text, whatsapp text, plan text, plan_vence date,
  aprobado boolean, es_admin boolean, clientes bigint, creado timestamptz,
  invitado_por uuid, invitado_por_nombre text, premio_invitacion date, ya_pago boolean
)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.phone, p.whatsapp, p.plan, p.plan_vence, p.aprobado, p.es_admin,
         (select count(*) from clientes c where c.prestamista_id = p.id),
         p.created_at,
         p.invitado_por,
         (select coalesce(nullif(trim(i.negocio), ''), i.nombre) from profiles i
           where i.id = p.invitado_por),
         p.premio_invitacion,
         exists (select 1 from pagos_planes pp where pp.prestamista_id = p.id and pp.monto > 0)
  from profiles p
  where public.es_admin()
  order by p.aprobado, p.created_at desc
$$;
