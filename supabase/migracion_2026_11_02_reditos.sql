-- Solo réditos (02-11-2026).
--
-- Un tercer método de interés para los préstamos nuevos: "solo réditos
-- (capital al final)". Cada cuota paga nada más el interés del monto
-- prestado y la ÚLTIMA cuota paga el interés más todo el capital.
-- Ej.: 10,000 al 10% mensual en 3 cuotas mensuales → 1,000, 1,000 y 11,000.
--
-- Solo cambia la regla de prestamos.tipo_interes para que acepte 'reditos'.
-- Los préstamos que ya existen no se tocan ('fijo' y 'saldo' siguen igual).
--
-- ⚠️ Correr ANTES de publicar la versión de la app que deja elegir réditos
-- (si no, al confirmar un préstamo de réditos la base de datos lo rechaza).
-- Se puede correr más de una vez sin problema.

alter table prestamos add column if not exists tipo_interes text not null default 'fijo';

alter table prestamos drop constraint if exists prestamos_tipo_interes_check;
alter table prestamos add constraint prestamos_tipo_interes_check
  check (tipo_interes in ('saldo', 'fijo', 'reditos'));
