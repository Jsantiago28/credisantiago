-- Errores de la app y GPS de los cobros (18-10-2026).
--
-- 1. Cuando la app falla en el teléfono o el navegador de alguien, guarda el
--    error aquí (sin datos de clientes) y el admin lo ve en su panel. Así se
--    sabe de las fallas sin esperar a que el prestamista avise.
-- 2. Cada cobro guarda dónde se hizo (si el teléfono dio permiso de
--    ubicación): el prestamista ve en el mapa dónde cobró cada cobrador.
--
-- Se puede correr más de una vez sin problema.

-- 1. Errores ------------------------------------------------------------------
create table if not exists errores_app (
  id uuid primary key default uuid_generate_v4(),
  creado timestamptz not null default now(),
  usuario uuid default auth.uid(),
  version text,
  plataforma text,
  pantalla text,
  mensaje text not null check (char_length(mensaje) <= 2000),
  detalle text check (char_length(detalle) <= 8000)
);
create index if not exists idx_errores_app_creado on errores_app(creado desc);

alter table errores_app enable row level security;

-- Cualquiera que use la app puede reportar (también el formulario público);
-- solo el admin los ve y los borra.
drop policy if exists "errores_reportar" on errores_app;
create policy "errores_reportar" on errores_app
  for insert to anon, authenticated with check (true);

drop policy if exists "errores_ver_admin" on errores_app;
create policy "errores_ver_admin" on errores_app
  for select using (public.es_admin());

drop policy if exists "errores_borrar_admin" on errores_app;
create policy "errores_borrar_admin" on errores_app
  for delete using (public.es_admin());

-- 2. Dónde se hizo cada cobro -------------------------------------------------
alter table pagos add column if not exists lat double precision;
alter table pagos add column if not exists lng double precision;
