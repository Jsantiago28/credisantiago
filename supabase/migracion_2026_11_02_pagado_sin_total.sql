-- ============================================================
-- El cobrador no puede dar por pagado un préstamo viejo sin total
-- ============================================================
-- Lo encontraron las pruebas de la base de datos (supabase/tests): los
-- préstamos viejos no tienen monto_total guardado, y la regla contaba
-- que debían RD$0, así que el cobrador podía marcarlos "pagado" sin
-- cobrar. Ahora, si no hay total, se exige por lo menos lo prestado.
-- Se puede correr más de una vez.

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
        select coalesce(sum(p.monto - p.monto_mora + p.descuento), 0) into cubierto
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
