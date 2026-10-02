-- ==========================================================
-- MIGRACIÓN: entregas de los cobradores (cuadre de caja, 30-09-2026)
-- ==========================================================
-- Al final del día el cobrador le entrega al prestamista lo que cobró. En
-- Reportes → Caja del día → "Por cobrador", el prestamista anota cuánto
-- recibió y la app le dice si cuadra, si falta o si sobra.
--
-- Se guarda lo que el cobrador había cobrado en ese momento (cobrado) para
-- avisar si después se anuló o se agregó un cobro de ese día.
-- La entrega la anota y la borra solo el prestamista; el cobrador solo
-- puede verla (para saber que su jefe ya la recibió).
--
-- Correr DESPUÉS de migracion_2026_09_30_cobradores.sql.
-- Se puede correr más de una vez sin problema.

create table if not exists entregas_cobrador (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  cobrador_id uuid not null references cobradores(id) on delete cascade,
  fecha date not null,                 -- el día de los cobros
  cobrado numeric(12,2) not null,      -- lo que había cobrado al anotar la entrega
  entregado numeric(12,2) not null check (entregado >= 0),
  nota text,                           -- ej. "mañana trae los 500 que faltan"
  created_at timestamptz default now(),
  unique (cobrador_id, fecha)
);

create index if not exists idx_entregas_prestamista_fecha on entregas_cobrador (prestamista_id, fecha);

alter table entregas_cobrador enable row level security;

drop policy if exists "entregas_dueno" on entregas_cobrador;
create policy "entregas_dueno" on entregas_cobrador
  for all using (auth.uid() = prestamista_id) with check (auth.uid() = prestamista_id);

drop policy if exists "entregas_cobrador_ver" on entregas_cobrador;
create policy "entregas_cobrador_ver" on entregas_cobrador
  for select using (cobrador_id = public.mi_cobrador());

-- La entrega tiene que ser de un cobrador del mismo prestamista.
create or replace function public.validar_entrega() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from cobradores
                  where id = new.cobrador_id and prestamista_id = new.prestamista_id) then
    raise exception 'Ese cobrador no es tuyo';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_entrega on entregas_cobrador;
create trigger trg_validar_entrega
  before insert or update on entregas_cobrador
  for each row execute function public.validar_entrega();
