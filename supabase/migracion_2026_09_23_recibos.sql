-- ==========================================================
-- MIGRACIÓN: número de recibo consecutivo por prestamista
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de publicar la versión de la app
-- con recibos: esa versión lee pagos.numero_recibo.
--
-- Cada prestamista tiene su propia numeración (#000001, #000002, ...).
-- La asigna la base de datos al guardar el pago, así dos cobros al mismo
-- tiempo nunca reciben el mismo número.
-- Los pagos que ya existen se numeran por fecha de cobro.

alter table pagos add column if not exists numero_recibo int;

with numerados as (
  select id,
         row_number() over (partition by prestamista_id order by fecha_pago, created_at, id) as n
  from pagos
)
update pagos p
set numero_recibo = numerados.n
from numerados
where p.id = numerados.id and p.numero_recibo is null;

create unique index if not exists pagos_numero_recibo_unico
  on pagos (prestamista_id, numero_recibo);

create or replace function asignar_numero_recibo() returns trigger
language plpgsql as $$
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

drop trigger if exists trg_numero_recibo on pagos;
create trigger trg_numero_recibo
  before insert on pagos
  for each row execute function asignar_numero_recibo();
