-- ==========================================================
-- MIGRACIÓN: anular cobros mal digitados
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de usar la versión de la app con
-- "Anular cobro": esa versión lee y guarda estas columnas. Sin ellas,
-- Inicio, Cobrar y Reportes no cargan.
--
-- Un cobro anulado NO se borra: queda con la marca, la fecha y el motivo,
-- para que haya rastro. No cuenta para el balance, la mora ni los reportes,
-- y su número de recibo no se reusa.
-- Se puede correr más de una vez sin problema.

alter table pagos add column if not exists anulado boolean not null default false;
alter table pagos add column if not exists anulado_en timestamptz;
alter table pagos add column if not exists motivo_anulacion text;
