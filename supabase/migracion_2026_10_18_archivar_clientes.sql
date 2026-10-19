-- Eliminar (archivar) clientes (18-10-2026).
--
--  * El prestamista puede quitar de su lista a un cliente que no tiene
--    préstamo en la calle. No se borra: queda ARCHIVADO (con sus préstamos
--    pagados, cobros y fotos) y se puede restaurar cuando quiera. Así la caja
--    y los reportes de días pasados no cambian.
--  * Los archivados no cuentan para el límite de clientes del plan. Al
--    restaurar uno, sí se revisa el límite.
--  * El cobrador no puede archivar (proteger_cliente ya solo le deja cambiar
--    la ubicación).
--
-- Correr DESPUÉS de migracion_2026_10_14_registro.sql.
-- Se puede correr más de una vez sin problema.

-- 1. Cuándo se archivó (null = está en la lista) ----------------------------
alter table clientes add column if not exists archivado_en timestamptz;

-- 2. El límite del plan cuenta solo los clientes que están en la lista ------
create or replace function public.validar_limite_clientes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  limite int := coalesce(public.limite_clientes(new.prestamista_id), 0);
  actuales int;
begin
  -- Al guardar cambios de un cliente que ya estaba en la lista, no se revisa.
  if tg_op = 'UPDATE' and not (old.archivado_en is not null and new.archivado_en is null) then
    return new;
  end if;
  if new.archivado_en is not null then
    return new;
  end if;
  select count(*) into actuales from clientes
   where prestamista_id = new.prestamista_id and archivado_en is null and id <> new.id;
  if actuales >= limite then
    raise exception 'LIMITE_PLAN: tu plan permite % clientes', limite;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_limite_clientes on clientes;
create trigger trg_limite_clientes
  before insert or update of archivado_en on clientes
  for each row execute function public.validar_limite_clientes();

-- 3. No se archiva a quien tiene un préstamo en la calle --------------------
create or replace function public.validar_archivar_cliente() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.archivado_en is not null and old.archivado_en is null
     and exists (select 1 from prestamos
                  where cliente_id = new.id
                    and estado in ('en_calle', 'por_cobrar', 'atrasado')) then
    raise exception 'TIENE_PRESTAMO: el cliente tiene un préstamo en la calle';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_archivar_cliente on clientes;
create trigger trg_archivar_cliente
  before update of archivado_en on clientes
  for each row execute function public.validar_archivar_cliente();

-- 4. El panel del admin cuenta solo los clientes en la lista (misma función
--    de migracion_2026_10_14_registro.sql, con ese único cambio) ------------
create or replace function public.admin_prestamistas()
returns table (
  id uuid, nombre text, telefono text, whatsapp text, plan text, plan_vence date,
  aprobado boolean, es_admin boolean, clientes bigint, creado timestamptz,
  invitado_por uuid, invitado_por_nombre text, premio_invitacion date, ya_pago boolean,
  cedula text, cedula_frente_url text, cedula_reverso_url text
)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.phone, p.whatsapp, p.plan, p.plan_vence, p.aprobado, p.es_admin,
         (select count(*) from clientes c
           where c.prestamista_id = p.id and c.archivado_en is null),
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
