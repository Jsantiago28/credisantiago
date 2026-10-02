-- ==========================================================
-- MIGRACIÓN: cierres de caja (Reportes → Caja por día)
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de usar "Cerrar caja".
-- Sin esta tabla, la Caja por día se ve igual, pero no se pueden guardar
-- ni ver los cierres.
--
-- Un cierre es el resumen de un día guardado por el prestamista (total,
-- cuotas, mora, cantidad de cobros y una nota). Queda hasta que él lo
-- borre. Borrar un cierre NO toca los cobros: esos son el historial de
-- cada préstamo y no se borran.
-- Se puede correr más de una vez sin problema.

create table if not exists cierres_caja (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  fecha date not null,                 -- el día que se cierra
  total numeric(12,2) not null,        -- todo lo recibido (sin anulados)
  cuotas numeric(12,2) not null,       -- de eso, a cuotas
  mora numeric(12,2) not null,         -- de eso, a mora
  cantidad_cobros int not null,
  nota text,                           -- ej. "le entregué RD$8,000 a Juan"
  created_at timestamptz default now(),
  unique (prestamista_id, fecha)
);

alter table cierres_caja enable row level security;

drop policy if exists "cierres_all_own" on cierres_caja;
create policy "cierres_all_own" on cierres_caja
  for all using (auth.uid() = prestamista_id) with check (auth.uid() = prestamista_id);
