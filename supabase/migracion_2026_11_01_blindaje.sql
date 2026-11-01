-- Blindaje contra trampas (01-11-2026), según la revisión de seguridad.
--
--  1. Cobros: el monto siempre positivo y la mora entre 0 y el monto. Un
--     cobrador no puede marcar un cobro como "importado" (no saldría en la
--     caja), ni anulado, ni con descuento.
--  2. Fotos: un logo o una cédula del prestamista solo cuentan si están en
--     SU carpeta (antes, poniendo de "logo" la ubicación de la cédula de un
--     cliente, esa foto quedaba pública).
--  3. Préstamos: el cobrador solo puede marcar "pagado" si los cobros cubren
--     lo que se debe, y solo mueve la próxima fecha justo después de cobrar.
--  4. Solicitudes: la fecha, la IP y la aceptación de privacidad las pone la
--     base de datos (antes se podía saltar el freno de 30 por hora).
--  5. Fotos que sube quien no tiene cuenta: solo cara, cédula y evidencias
--     de una solicitud; cada prestamista sube libre solo en su carpeta.
--  6. Invitación de cobrador: solo con el correo ya confirmado.
--  7. Clientes archivados: no se crean archivados (se saltaban el límite
--     del plan) y no se les presta.
--  8. Errores de la app: textos con tope.
--  9. Registro: las cuentas nuevas entran aprobadas, siempre (plan Gratis
--     con sus límites). Ya no existe "esperar la aprobación del admin".
--
-- Correr DESPUÉS de migracion_2026_10_19_sin_conexion.sql.
-- Se puede correr más de una vez sin problema.

-- 1. Cobros ---------------------------------------------------------------------
alter table pagos drop constraint if exists pagos_monto_chk;
alter table pagos add constraint pagos_monto_chk check (monto > 0);
alter table pagos drop constraint if exists pagos_mora_chk;
alter table pagos add constraint pagos_mora_chk check (monto_mora >= 0 and monto_mora <= monto);

create or replace function public.vigilar_cobro() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  motivos text[] := '{}';
  horas numeric;
begin
  new.registrado_en := now();

  -- El prestamista (o el admin) con sus propios cobros: sin vigilancia.
  if auth.uid() is null or auth.uid() = new.prestamista_id or public.es_admin() then
    return new;
  end if;

  -- Desde aquí, un cobrador. El número de recibo, la marca de revisar, el
  -- método, la anulación y el descuento no los decide él.
  new.numero_recibo := null;
  new.revisar := null;
  new.anulado := false;
  new.descuento := 0;
  if new.metodo is distinct from 'transferencia' then
    new.metodo := 'efectivo';
  end if;

  if not new.sin_conexion then
    new.fecha_pago := now();
    new.reloj_telefono := null;
    return new;
  end if;

  if new.fecha_pago is null or new.fecha_pago > now() + interval '10 minutes' then
    motivos := motivos || 'la hora del cobro estaba en el futuro'::text;
    new.fecha_pago := now();
  end if;

  if new.reloj_telefono is null
     or abs(extract(epoch from (now() - new.reloj_telefono))) > 600 then
    motivos := motivos || 'el reloj del teléfono no tenía la hora correcta'::text;
  end if;

  horas := extract(epoch from (now() - new.fecha_pago)) / 3600;
  if horas > 12 then
    motivos := motivos || format('se subió %s horas después de cobrarlo', round(horas))::text;
  end if;

  if exists (select 1 from pagos p
              where p.prestamo_id = new.prestamo_id
                and not p.anulado
                and p.cobrador_id is distinct from public.mi_cobrador()
                and p.registrado_en > new.fecha_pago) then
    motivos := motivos || 'alguien más le cobró a este préstamo mientras no había señal'::text;
  end if;

  if array_length(motivos, 1) > 0 then
    new.revisar := array_to_string(motivos, '; ');
  end if;
  return new;
end;
$$;

-- 2. Fotos del prestamista: solo en su propia carpeta ---------------------------
create or replace function public.es_logo_de_prestamista(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
    where p.recibo_logo = ruta and split_part(ruta, '/', 1) = p.id::text
  )
$$;

create or replace function public.es_logo_de_mi_jefe(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
    where p.id = public.cobrador_jefe() and p.recibo_logo = ruta
      and split_part(ruta, '/', 1) = p.id::text
  )
$$;

create or replace function public.es_cedula_de_prestamista(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles p
    where ruta in (p.cedula_frente_url, p.cedula_reverso_url)
      and split_part(ruta, '/', 1) = p.id::text
  )
$$;

-- Las fotos "viejas" (de antes de las carpetas) no tienen "/": una ruta con
-- carpeta nunca entra por aquí.
create or replace function public.es_foto_vieja_propia(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select position('/' in ruta) = 0 and (
    exists (
      select 1 from solicitudes s
      where s.prestamista_id = auth.uid()
        and (ruta in (s.foto_cara_url, s.foto_cedula_frente_url, s.foto_cedula_reverso_url)
             or ruta = any(s.evidencias_ingresos))
    ) or exists (
      select 1 from clientes c
      where c.prestamista_id = auth.uid()
        and (ruta in (c.foto_cara_url, c.foto_cedula_frente_url, c.foto_cedula_reverso_url)
             or ruta = any(c.evidencias_ingresos))
    )
  )
$$;

-- El logo y la cédula del perfil tienen que estar en la carpeta del dueño.
create or replace function public.proteger_fotos_perfil() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.es_admin() then
    return new;
  end if;
  if (new.recibo_logo is not null and split_part(new.recibo_logo, '/', 1) <> new.id::text)
     or (new.cedula_frente_url is not null and split_part(new.cedula_frente_url, '/', 1) <> new.id::text)
     or (new.cedula_reverso_url is not null and split_part(new.cedula_reverso_url, '/', 1) <> new.id::text) then
    raise exception 'Esa foto no es de tu carpeta';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_proteger_fotos_perfil on profiles;
create trigger trg_proteger_fotos_perfil
  before insert or update of recibo_logo, cedula_frente_url, cedula_reverso_url on profiles
  for each row execute function public.proteger_fotos_perfil();

-- 3. Préstamos: lo que puede cambiar el cobrador --------------------------------
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
        if cubierto < coalesce(old.monto_total, 0) - 0.01 then
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

-- 4. Solicitudes: lo que no se puede inventar ----------------------------------
create or replace function public.frenar_solicitudes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- El prestamista o el admin cargando una a mano: sin freno.
  if auth.uid() is not null and (auth.uid() = new.prestamista_id or public.es_admin()) then
    return new;
  end if;
  new.estado := 'nueva';
  new.created_at := now();
  new.ip_address := null;
  if new.acepto_privacidad_en is null then
    raise exception 'Hay que aceptar la política de privacidad';
  end if;
  new.acepto_privacidad_en := now();
  if (select count(*) from solicitudes
       where prestamista_id = new.prestamista_id
         and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'DEMASIADAS_SOLICITUDES: intenta de nuevo más tarde';
  end if;
  if new.cedula is not null and (select count(*) from solicitudes
       where prestamista_id = new.prestamista_id
         and cedula = new.cedula
         and created_at > now() - interval '1 day') >= 3 then
    raise exception 'DEMASIADAS_SOLICITUDES: ya enviaste esta solicitud hoy';
  end if;
  return new;
end;
$$;

-- 5. Quién sube fotos y adónde ---------------------------------------------------
drop policy if exists "fotos_subir_a_carpeta_de_prestamista" on storage.objects;
create policy "fotos_subir_a_carpeta_de_prestamista" on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'solicitudes-fotos'
    and public.es_carpeta_de_prestamista((storage.foldername(name))[1])
    and (
      -- El prestamista, en su propia carpeta: cualquier foto suya.
      (storage.foldername(name))[1] = auth.uid()::text
      -- Cualquiera llenando una solicitud: solo cara, cédula y evidencias.
      or storage.filename(name) ~ '^(cara|cedula_f|cedula_r|solicitud_evidencia)_[0-9]+_[0-9]+\.jpg$'
    )
  );

-- 6. Invitación de cobrador solo con el correo confirmado -----------------------
create or replace function public.aceptar_invitacion_cobrador() returns uuid
language plpgsql security definer set search_path = public as $$
declare
  correo text := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  registro uuid;
begin
  if auth.uid() is null or correo = '' then return null; end if;
  if (select email_confirmed_at from auth.users where id = auth.uid()) is null then
    return null;
  end if;
  if exists (select 1 from profiles where id = auth.uid()) then return null; end if;

  select id into registro from cobradores
   where email = correo and activo and (user_id is null or user_id = auth.uid())
   limit 1;
  if registro is null then return null; end if;

  perform set_config('app.aceptando_cobrador', 'si', true);
  update cobradores set user_id = auth.uid() where id = registro and user_id is null;
  return registro;
end;
$$;

-- 7. Clientes archivados -------------------------------------------------------
create or replace function public.validar_limite_clientes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  limite int := coalesce(public.limite_clientes(new.prestamista_id), 0);
  actuales int;
begin
  -- Un cliente nuevo siempre entra en la lista (no se crea ya archivado).
  if tg_op = 'INSERT' then
    new.archivado_en := null;
  end if;
  -- Al guardar cambios de un cliente que ya estaba en la lista, no se revisa.
  if tg_op = 'UPDATE' and not (old.archivado_en is not null and new.archivado_en is null) then
    return new;
  end if;
  select count(*) into actuales from clientes
   where prestamista_id = new.prestamista_id and archivado_en is null and id <> new.id;
  if actuales >= limite then
    raise exception 'LIMITE_PLAN: tu plan permite % clientes', limite;
  end if;
  return new;
end;
$$;

create or replace function public.no_prestar_a_archivado() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from clientes c where c.id = new.cliente_id and c.archivado_en is not null) then
    raise exception 'Ese cliente está eliminado: restáuralo antes de prestarle';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_no_prestar_a_archivado on prestamos;
create trigger trg_no_prestar_a_archivado
  before insert on prestamos
  for each row execute function public.no_prestar_a_archivado();

-- 8. Errores de la app: textos con tope ---------------------------------------
update errores_app set version = left(version, 50), plataforma = left(plataforma, 50),
  pantalla = left(pantalla, 200)
 where char_length(version) > 50 or char_length(plataforma) > 50 or char_length(pantalla) > 200;
alter table errores_app drop constraint if exists errores_app_largos_chk;
alter table errores_app add constraint errores_app_largos_chk check (
  char_length(coalesce(version, '')) <= 50
  and char_length(coalesce(plataforma, '')) <= 50
  and char_length(coalesce(pantalla, '')) <= 200);

-- 9. Las cuentas nuevas entran aprobadas, siempre ------------------------------
update ajustes_app set registro_requiere_aprobacion = false where id = 1;

create or replace function public.proteger_plan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Sin usuario de la app (SQL Editor de Supabase) o admin: se permite.
  if auth.uid() is null or public.es_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.plan := 'gratis';
    new.plan_vence := null;
    new.es_admin := false;
    new.aprobado := true;
  elsif new.plan is distinct from old.plan
     or new.plan_vence is distinct from old.plan_vence
     or new.aprobado is distinct from old.aprobado
     or new.es_admin is distinct from old.es_admin then
    raise exception 'Solo el administrador puede cambiar el plan o la aprobación';
  end if;
  return new;
end;
$$;
