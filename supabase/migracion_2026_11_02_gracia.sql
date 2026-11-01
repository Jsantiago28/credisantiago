-- 7 días de gracia al vencer el plan pagado (02-11-2026).
--
-- Cuando vence el plan pagado, el prestamista sigue con su plan 7 días más
-- (clientes y cobradores) para que renueve sin perder nada. Pasados esos
-- días, cuenta como Gratis. La app usa la misma regla (lib/logic/planes.dart,
-- diasDeGracia).
--
-- Correr DESPUÉS de migracion_2026_11_01_blindaje.sql.
-- Se puede correr más de una vez sin problema.

create or replace function public.limite_clientes(prestamista uuid) returns int
language sql stable security definer set search_path = public as $$
  select case
    when not p.aprobado then 0
    else coalesce(
      (select pl.max_clientes from planes pl
        where pl.id = case when p.plan_vence is not null and p.plan_vence + 7 < current_date
                           then 'gratis' else p.plan end),
      2147483647)                       -- plan sin límite
  end
  from profiles p where p.id = prestamista
$$;

create or replace function public.limite_cobradores(prestamista uuid) returns int
language sql stable security definer set search_path = public as $$
  select case
    when not p.aprobado then 0
    else coalesce(
      (select pl.max_cobradores from planes pl
        where pl.id = case when p.plan_vence is not null and p.plan_vence + 7 < current_date
                           then 'gratis' else p.plan end),
      2147483647)                       -- plan sin límite
  end
  from profiles p where p.id = prestamista
$$;

-- Que sigan cerradas para quien no tiene cuenta (como en la de seguridad).
revoke all on function public.limite_clientes(uuid) from public, anon;
grant execute on function public.limite_clientes(uuid) to authenticated;
revoke all on function public.limite_cobradores(uuid) from public, anon;
grant execute on function public.limite_cobradores(uuid) to authenticated;
