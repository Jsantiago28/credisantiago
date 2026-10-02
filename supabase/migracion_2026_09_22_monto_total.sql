-- ==========================================================
-- MIGRACIÓN 2026-09-22: total prometido del préstamo
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de publicar la versión de la app
-- que redondea las cuotas a pesos enteros: esa versión guarda monto_total
-- al confirmar un préstamo, y sin esta columna el guardado falla.
--
-- monto_total: lo que el cliente debe devolver en total (pesos enteros).
-- Las cuotas son pesos enteros y la última absorbe la diferencia, por eso
-- ya no alcanza con cuota × cantidad_cuotas.
--
-- Préstamos existentes: se dejan en NULL a propósito. La app sigue
-- usando cuota × cantidad_cuotas para ellos (lo que se les prometió).

alter table prestamos add column if not exists cantidad_cuotas int;
alter table prestamos add column if not exists monto_total numeric(12,2);
