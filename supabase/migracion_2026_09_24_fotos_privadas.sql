-- ==========================================================
-- MIGRACIÓN: fotos privadas (cédulas y evidencias de ingresos)
-- ==========================================================
-- Correr en Supabase (SQL Editor) JUNTO con la versión de la app que pide
-- enlaces temporales: desde aquí las fotos ya no tienen enlace público.
--
-- Antes: bucket "solicitudes-fotos" público. Cualquiera con el enlace veía
--        la cédula o el volante de pago de un cliente.
-- Ahora: - el bucket es privado;
--        - las fotos nuevas van en una carpeta por prestamista
--          (<id del prestamista>/archivo.jpg);
--        - cualquiera puede SUBIR (el formulario del link no tiene login),
--          pero solo a la carpeta de un prestamista que exista;
--        - solo el prestamista dueño puede VER sus fotos (la app pide un
--          enlace que vence en 1 hora);
--        - las fotos viejas (sueltas, sin carpeta) solo las ve el
--          prestamista cuyo cliente o solicitud las usa.
-- En la base de datos se guarda la ubicación del archivo, no un enlace.
--
-- Se puede correr sola y más de una vez sin problema.

-- 0. Columnas que usa esta migración (por si todavía no se corrieron las
--    migraciones de evidencias / ingresos y vivienda).
alter table solicitudes add column if not exists evidencias_ingresos text[] not null default '{}';
alter table clientes add column if not exists evidencias_ingresos text[] not null default '{}';
alter table profiles add column if not exists exigir_evidencias boolean not null default false;

-- 1. Bucket privado.
update storage.buckets set public = false where id = 'solicitudes-fotos';

-- 2. Quitar las reglas anteriores de este bucket (por ejemplo una de
--    "lectura pública"), para que no sigan dejando ver las fotos.
do $$
declare r record;
begin
  for r in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (coalesce(qual, '') || coalesce(with_check, '')) like '%solicitudes-fotos%'
  loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;

-- 3. En la base de datos: de enlace público a ubicación del archivo.
create or replace function _ruta_foto(valor text) returns text
language sql immutable as $$
  select case
    when valor is null then null
    else regexp_replace(valor, '^.*/object/(public|sign)/solicitudes-fotos/([^?]*).*$', '\2')
  end
$$;

update solicitudes set
  foto_cara_url = _ruta_foto(foto_cara_url),
  foto_cedula_frente_url = _ruta_foto(foto_cedula_frente_url),
  foto_cedula_reverso_url = _ruta_foto(foto_cedula_reverso_url),
  evidencias_ingresos = array(select _ruta_foto(e) from unnest(evidencias_ingresos) e);

update clientes set
  foto_cara_url = _ruta_foto(foto_cara_url),
  foto_cedula_frente_url = _ruta_foto(foto_cedula_frente_url),
  foto_cedula_reverso_url = _ruta_foto(foto_cedula_reverso_url),
  evidencias_ingresos = array(select _ruta_foto(e) from unnest(evidencias_ingresos) e);

drop function _ruta_foto(text);

-- 4. Funciones que usan las reglas (security definer: consultan sin las
--    restricciones del que sube o mira, pero solo responden sí o no).

-- ¿La carpeta es de un prestamista que existe?
create or replace function public.es_carpeta_de_prestamista(carpeta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id::text = carpeta)
$$;

-- ¿Esta foto vieja (sin carpeta) la usa un cliente o solicitud del
-- prestamista que la pide?
create or replace function public.es_foto_vieja_propia(ruta text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
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
$$;

-- 5. Reglas nuevas.
create policy "fotos_subir_a_carpeta_de_prestamista" on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'solicitudes-fotos'
    and public.es_carpeta_de_prestamista((storage.foldername(name))[1])
  );

create policy "fotos_ver_solo_el_dueno" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'solicitudes-fotos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.es_foto_vieja_propia(name)
    )
  );

-- 6. Revisa lo que quedó: no debe haber ninguna regla de "select" para
--    anon/public sobre storage.objects (si aparece una, bórrala desde
--    Storage > Policies).
select policyname, cmd, roles from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by policyname;
