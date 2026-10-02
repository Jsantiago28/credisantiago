-- ==========================================================
-- MIGRACIÓN: mora (recargo por atraso)
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de publicar la versión de la app
-- con mora: esa versión guarda estas columnas al prestar y al cobrar, y
-- sin ellas el guardado falla.
--
-- prestamos.mora_diaria: % diario sobre lo que falta de cada cuota vencida.
-- prestamos.dias_gracia: días completos después del vencimiento sin recargo.
--   Se fijan en cada préstamo al prestar (la app propone 5% y 1 día).
--   Préstamos que ya están en la calle quedan con 0% (no se pactó mora).
-- pagos.monto_mora: de cada cobro, cuánto fue a mora (el resto, a cuotas).
--   Los pagos anteriores quedan en 0: todo fue a cuotas.

alter table prestamos add column if not exists mora_diaria numeric(5,2) not null default 0;
alter table prestamos add column if not exists dias_gracia int not null default 1;
alter table pagos add column if not exists monto_mora numeric(12,2) not null default 0;
