-- Saldar un préstamo antes de tiempo (18-10-2026).
--
--  * Si el cliente quiere pagar todo antes, solo se le cobra el interés
--    hasta ese día (más 1 día de cierre). El interés de las cuotas que no
--    llegaron se le descuenta.
--  * El cobro guarda ese descuento aparte (pagos.descuento): cuenta para
--    dejar el préstamo saldado, pero NO es dinero recibido (la caja suma
--    solo pagos.monto, como siempre).
--  * Solo el prestamista puede hacer descuentos: el cobrador no.
--
-- Correr DESPUÉS de migracion_2026_09_30_cobradores.sql.
-- Se puede correr más de una vez sin problema.

-- 1. El descuento de cada cobro (0 en los cobros normales) -------------------
alter table pagos add column if not exists descuento numeric not null default 0;
alter table pagos drop constraint if exists pagos_descuento_check;
alter table pagos add constraint pagos_descuento_check check (descuento >= 0);

-- 2. El cobrador cobra, pero sin descuento -----------------------------------
drop policy if exists "pagos_cobrador_cobrar" on pagos;
create policy "pagos_cobrador_cobrar" on pagos
  for insert with check (
    prestamista_id = public.cobrador_jefe()
    and public.es_prestamo_de_mi_ruta(prestamo_id)
    and not anulado
    and descuento = 0
  );
