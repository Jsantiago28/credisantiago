-- Cargos aparte (03-11-2026).
--
-- Un cobro que NO baja lo que el cliente debe: un interés extra, un gasto
-- legal o algo que el prestamista acordó con el cliente. Es ganancia del
-- prestamista y el cliente sigue debiendo sus cuotas igual.
--
--  * pagos.cargo: cuánto del cobro es cargo (0 en los cobros normales).
--  * pagos.cargo_tipo: 'interes', 'legal', 'acuerdo' u 'otro'.
--  * pagos.cargo_nota: por qué se cobró (obligatoria si hay cargo).
--  * Solo el prestamista cobra cargos: el cobrador no.
--  * La regla de "pagado" no cuenta los cargos como pago de cuotas.
-- Se puede correr más de una vez.

alter table pagos add column if not exists cargo numeric(12,2) not null default 0;
alter table pagos add column if not exists cargo_tipo text;
alter table pagos add column if not exists cargo_nota text;

alter table pagos drop constraint if exists pagos_cargo_chk;
alter table pagos add constraint pagos_cargo_chk check (
  cargo >= 0
  and cargo + monto_mora <= monto
  and (cargo = 0 or (cargo_tipo in ('interes', 'legal', 'acuerdo', 'otro')
                     and length(btrim(coalesce(cargo_nota, ''))) between 1 and 300))
);

-- El cobrador cobra, pero sin descuento ni cargos.
drop policy if exists "pagos_cobrador_cobrar" on pagos;
create policy "pagos_cobrador_cobrar" on pagos
  for insert with check (
    prestamista_id = public.cobrador_jefe()
    and public.es_prestamo_de_mi_ruta(prestamo_id)
    and not anulado
    and descuento = 0
    and cargo = 0
  );

create or replace function public.proteger_prestamo() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  cubierto numeric;
begin
  if auth.uid() is not null and auth.uid() is distinct from old.prestamista_id
     and not public.es_admin() then
    if (to_jsonb(new) - 'proximo_pago' - 'estado') is distinct from
       (to_jsonb(old) - 'proximo_pago' - 'estado') then
      raise exception 'El cobrador no puede cambiar el préstamo';
    end if;
    if new.estado is distinct from old.estado then
      if not (old.estado in ('en_calle', 'pagado') and new.estado in ('en_calle', 'pagado')) then
        raise exception 'El cobrador no puede cambiar el préstamo';
      end if;
      -- Solo "pagado" si los cobros de verdad cubren lo que se debe.
      if new.estado = 'pagado' then
        select coalesce(sum(p.monto - p.monto_mora - p.cargo + p.descuento), 0) into cubierto
          from pagos p where p.prestamo_id = old.id and not p.anulado;
        if cubierto < coalesce(old.monto_total, old.monto, 0) - 0.01 then
          raise exception 'El préstamo todavía debe: no se puede marcar pagado';
        end if;
      end if;
    end if;
    -- La próxima fecha solo se mueve justo después de un cobro suyo.
    if new.proximo_pago is distinct from old.proximo_pago
       and not exists (select 1 from pagos p
                        where p.prestamo_id = old.id
                          and p.cobrador_id = public.mi_cobrador()
                          and p.registrado_en > now() - interval '5 minutes') then
      new.proximo_pago := old.proximo_pago;
    end if;
  end if;
  return new;
end;
$$;
