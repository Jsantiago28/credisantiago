-- ==========================================================
-- MIGRACIÓN: gestiones y acuerdos de cobro
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de usar "Anotar gestión".
-- Sin esta tabla la app sigue funcionando igual, pero no se pueden
-- guardar ni ver las gestiones.
--
-- Una gestión es cada vez que se le cobra o se le da seguimiento a un
-- cliente: una visita, una llamada, un WhatsApp. Se anota qué pasó
-- (pagó, prometió pagar, no estaba, se negó), el acuerdo por escrito y,
-- si prometió pagar, la fecha y el monto prometidos.
-- No se editan ni se borran: son el historial de cobro del cliente.
-- Se puede correr más de una vez sin problema.

create table if not exists gestiones (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  prestamo_id uuid not null references prestamos(id) on delete cascade,
  cliente_id uuid references clientes(id) on delete cascade,
  tipo text not null check (tipo in ('visita', 'llamada', 'whatsapp', 'otro')),
  resultado text not null
    check (resultado in ('pago', 'promesa', 'no_estaba', 'se_nego', 'otro')),
  acuerdo text,                          -- ej. "paga el viernes 2,000 y el resto el lunes"
  promesa_fecha date,                    -- si prometió pagar: para cuándo
  promesa_monto numeric(12,2),           -- y cuánto
  hecho_por uuid default auth.uid(),     -- quién la hizo (para cuando haya cobradores)
  created_at timestamptz default now()
);

create index if not exists idx_gestiones_prestamo on gestiones(prestamo_id);
create index if not exists idx_gestiones_prestamista on gestiones(prestamista_id);

alter table gestiones enable row level security;

-- Cada prestamista ve y anota solo las suyas. No hay política de
-- update ni delete: una gestión anotada queda como historial.
drop policy if exists "gestiones_select_own" on gestiones;
create policy "gestiones_select_own" on gestiones
  for select using (auth.uid() = prestamista_id);

drop policy if exists "gestiones_insert_own" on gestiones;
create policy "gestiones_insert_own" on gestiones
  for insert with check (auth.uid() = prestamista_id);
