-- Interés sobre saldo (17-10-2026).
--
-- Hasta ahora el interés se cobraba "fijo": sobre el monto prestado, todos
-- los períodos. Desde ahora los préstamos nuevos se calculan como en bancos
-- y cooperativas: sobre lo que todavía se debe, con cuota fija (sistema
-- francés). Con la misma tasa sale más barato para el cliente.
--
-- Cada préstamo guarda con qué método se hizo, para que los de antes sigan
-- cobrándose exactamente igual: todos los que ya existen quedan "fijo".
--
-- ⚠️ Correr ANTES de publicar la versión de la app que presta sobre saldo.
-- Se puede correr más de una vez sin problema.

alter table prestamos add column if not exists tipo_interes text not null default 'fijo';

alter table prestamos drop constraint if exists prestamos_tipo_interes_check;
alter table prestamos add constraint prestamos_tipo_interes_check
  check (tipo_interes in ('fijo', 'saldo'));
