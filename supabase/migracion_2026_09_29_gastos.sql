-- ==========================================================
-- MIGRACIÓN: gastos del negocio (Reportes → Gastos)
-- ==========================================================
-- Lo que el prestamista gasta para trabajar: gasolina, pago al cobrador,
-- recargas... Con esto la app muestra la ganancia real del mes:
--   interés cobrado + mora cobrada − gastos.
--
-- Un gasto se puede borrar si se anotó mal: no toca los préstamos ni los
-- cobros.
-- Se puede correr más de una vez sin problema.

create table if not exists gastos (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  fecha date not null default current_date,
  monto numeric(12,2) not null check (monto > 0),
  categoria text not null default 'otro'
    check (categoria in ('gasolina', 'cobrador', 'telefono', 'comida', 'transporte', 'otro')),
  nota text,                           -- ej. "moto de Juan"
  created_at timestamptz default now()
);

create index if not exists gastos_prestamista_fecha on gastos (prestamista_id, fecha);

alter table gastos enable row level security;

drop policy if exists "gastos_all_own" on gastos;
create policy "gastos_all_own" on gastos
  for all using (auth.uid() = prestamista_id) with check (auth.uid() = prestamista_id);
