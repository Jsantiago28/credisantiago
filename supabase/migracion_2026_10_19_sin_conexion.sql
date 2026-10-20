-- Cobrar sin internet, sin espacio para trampas (19-10-2026).
--
-- En la app de Android, si no hay señal, el cobro se guarda en el teléfono
-- (cifrado) y se sube solo cuando vuelve. La base de datos es la que decide
-- qué se acepta y qué hay que revisar:
--
--  * Cobros CON señal hechos por un cobrador: la fecha es SIEMPRE la del
--    servidor (antes un cobrador con conocimientos podía poner otra fecha
--    o su propio número de recibo; ya no).
--  * Cobros SIN señal: se acepta la hora del teléfono, pero se marcan para
--    que el prestamista los revise si:
--      - el reloj del teléfono no tenía la hora correcta al subirlos,
--      - la hora del cobro es del futuro (se cambia a la hora real),
--      - se subieron más de 12 horas después de cobrarlos,
--      - alguien más le cobró al mismo préstamo mientras tanto.
--  * El cobrador no puede quitar la marca ni cambiar el cobro (no tiene
--    permiso de editar cobros). Solo el prestamista marca "Ya lo revisé".
--
-- Correr DESPUÉS de migracion_2026_10_18_seguridad.sql.
-- Se puede correr más de una vez sin problema.

-- 1. Columnas ------------------------------------------------------------------
alter table pagos add column if not exists sin_conexion boolean not null default false;
-- Cuándo llegó de verdad al servidor (no se puede falsificar).
alter table pagos add column if not exists registrado_en timestamptz not null default now();
-- La hora que tenía el teléfono al subirlo (para ver si le cambiaron el reloj).
alter table pagos add column if not exists reloj_telefono timestamptz;
-- Por qué hay que revisarlo (null = sin novedad).
alter table pagos add column if not exists revisar text;

-- Los cobros de antes llegaron al servidor el mismo momento en que se hicieron.
update pagos set registrado_en = fecha_pago
 where not sin_conexion and fecha_pago is not null and registrado_en is distinct from fecha_pago;

-- 2. El vigilante de cada cobro -------------------------------------------------
-- Se llama "trg_a_..." para correr antes que el que pone el número de recibo.
create or replace function public.vigilar_cobro() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  motivos text[] := '{}';
  horas numeric;
begin
  new.registrado_en := now();

  -- El prestamista (o el admin) con sus propios cobros: sin vigilancia.
  if auth.uid() is null or auth.uid() = new.prestamista_id or public.es_admin() then
    return new;
  end if;

  -- Desde aquí, un cobrador. El número de recibo lo pone siempre la base de
  -- datos y la marca de revisar también.
  new.numero_recibo := null;
  new.revisar := null;

  if not new.sin_conexion then
    new.fecha_pago := now();
    new.reloj_telefono := null;
    return new;
  end if;

  if new.fecha_pago is null or new.fecha_pago > now() + interval '10 minutes' then
    motivos := motivos || 'la hora del cobro estaba en el futuro'::text;
    new.fecha_pago := now();
  end if;

  if new.reloj_telefono is null
     or abs(extract(epoch from (now() - new.reloj_telefono))) > 600 then
    motivos := motivos || 'el reloj del teléfono no tenía la hora correcta'::text;
  end if;

  horas := extract(epoch from (now() - new.fecha_pago)) / 3600;
  if horas > 12 then
    motivos := motivos || format('se subió %s horas después de cobrarlo', round(horas))::text;
  end if;

  if exists (select 1 from pagos p
              where p.prestamo_id = new.prestamo_id
                and not p.anulado
                and p.cobrador_id is distinct from public.mi_cobrador()
                and p.registrado_en > new.fecha_pago) then
    motivos := motivos || 'alguien más le cobró a este préstamo mientras no había señal'::text;
  end if;

  if array_length(motivos, 1) > 0 then
    new.revisar := array_to_string(motivos, '; ');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_a_vigilar_cobro on pagos;
create trigger trg_a_vigilar_cobro
  before insert on pagos
  for each row execute function public.vigilar_cobro();

-- Cobros por revisar, para encontrarlos rápido.
create index if not exists idx_pagos_revisar on pagos (prestamista_id) where revisar is not null;
