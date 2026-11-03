-- Pruebas de seguridad de la base de datos (pgTAP). Corren en GitHub sobre
-- una base de PRUEBA vacía (ver .github/workflows/pruebas-base-datos.yml).
-- Todo pasa dentro de una transacción que al final se deshace.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

-- Dos prestamistas (A y B) y un cliente con préstamo de A ---------------------
insert into auth.users (id, email, email_confirmed_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@prueba.do', now()),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@prueba.do', now());
insert into profiles (id, phone, slug, nombre, aprobado) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '8090000001', 'prestamista-a', 'A', true),
  ('bbbbbbbb-0000-0000-0000-000000000002', '8090000002', 'prestamista-b', 'B', true);
insert into clientes (id, prestamista_id, nombre, cedula, telefono) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Cliente de A', '00100000001', '8091111111'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Otro cliente de A, sin préstamo', '00100000002', '8092222222');
insert into prestamos (id, prestamista_id, cliente_id, monto, estado) values
  ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'cccccccc-0000-0000-0000-000000000001', 5000, 'en_calle');

-- Sin cuenta (anon) ------------------------------------------------------------
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';

select is((select count(*)::int from clientes), 0, 'Sin cuenta no se ven clientes');
select is((select count(*)::int from prestamos), 0, 'Sin cuenta no se ven préstamos');
select throws_ok($$ select public.limite_clientes('aaaaaaaa-0000-0000-0000-000000000001') $$,
  '42501', null, 'Sin cuenta no se puede preguntar el límite de clientes');

-- Prestamista B: no ve ni toca lo de A ----------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}';

select is((select count(*)::int from clientes), 0, 'B no ve los clientes de A');
select is((select count(*)::int from prestamos), 0, 'B no ve los préstamos de A');
select throws_ok($$
  insert into pagos (prestamo_id, prestamista_id, monto, metodo)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 100, 'efectivo') $$,
  '42501', null, 'B no puede anotar cobros en un préstamo de A');
update clientes set nombre = 'Cambiado por B' where id = 'cccccccc-0000-0000-0000-000000000001';

-- Prestamista A: ve lo suyo y la base rechaza lo raro -------------------------
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}';

select is((select nombre from clientes where id = 'cccccccc-0000-0000-0000-000000000001'),
  'Cliente de A', 'A ve su cliente y B no se lo pudo cambiar');
select throws_ok($$
  insert into pagos (prestamo_id, prestamista_id, monto, metodo)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 0, 'efectivo') $$,
  '23514', null, 'Un cobro de RD$0 en efectivo se rechaza');
select throws_ok($$
  insert into pagos (prestamo_id, prestamista_id, monto, metodo)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', -50, 'efectivo') $$,
  '23514', null, 'Un cobro negativo se rechaza');
select lives_ok($$
  insert into prestamos (prestamista_id, cliente_id, monto, estado, tipo_interes)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 3000, 'borrador', 'reditos') $$,
  'Se puede prestar con solo réditos');
select throws_ok($$
  insert into prestamos (prestamista_id, cliente_id, monto, estado, tipo_interes)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 3000, 'borrador', 'inventado') $$,
  '23514', null, 'Un tipo de interés inventado se rechaza');
select throws_ok($$
  insert into pagos (prestamo_id, prestamista_id, monto, metodo, cargo, cargo_tipo)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 500, 'efectivo', 500, 'legal') $$,
  '23514', null, 'Un cargo sin la nota de por qué se rechaza');
select lives_ok($$
  insert into pagos (prestamo_id, prestamista_id, monto, metodo, cargo, cargo_tipo, cargo_nota)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 500, 'efectivo', 500, 'legal', 'Carta del abogado') $$,
  'El prestamista puede cobrar un cargo aparte con su nota');

-- A elimina (archiva) el cliente sin préstamo: ya no se le puede prestar
update clientes set archivado_en = now() where id = 'cccccccc-0000-0000-0000-000000000002';
select throws_ok($$
  insert into prestamos (prestamista_id, cliente_id, monto, estado)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000002', 1000, 'borrador') $$,
  null, 'No se le presta a un cliente eliminado');

-- Cobrador de A: ve solo su ruta y no puede hacer trampas ----------------------
reset role;
set local request.jwt.claims to '{}'; -- como el dueño de la base, sin usuario
update profiles set plan = 'pro', plan_vence = current_date + 30
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
insert into auth.users (id, email, email_confirmed_at) values
  ('eeeeeeee-0000-0000-0000-000000000003', 'cobrador@prueba.do', now());
insert into cobradores (id, prestamista_id, nombre, email, user_id) values
  ('ffffffff-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Cobrador', 'cobrador@prueba.do', 'eeeeeeee-0000-0000-0000-000000000003');
insert into clientes (id, prestamista_id, nombre, cedula, telefono) values
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Cliente fuera de la ruta', '00100000003', '8093333333');
update clientes set cobrador_id = 'ffffffff-0000-0000-0000-000000000001'
 where id = 'cccccccc-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claims to '{"sub":"eeeeeeee-0000-0000-0000-000000000003","role":"authenticated"}';

select is((select count(*)::int from clientes), 1, 'El cobrador ve solo los clientes de su ruta');
-- Los 2 del cliente de su ruta (el de la calle y el borrador de réditos).
select is((select count(*)::int from prestamos), 2, 'El cobrador ve solo los préstamos de su ruta');
select lives_ok($$
  insert into pagos (prestamo_id, prestamista_id, monto, metodo)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 200, 'efectivo') $$,
  'El cobrador puede cobrar a un cliente de su ruta');
-- Con descuento y anulado: la base se los quita (o lo rechaza).
do $$ begin
  insert into pagos (prestamo_id, prestamista_id, monto, metodo, descuento, anulado)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 200, 'efectivo', 500, true);
exception when others then null;
end $$;
select throws_ok($$
  insert into pagos (prestamo_id, prestamista_id, monto, metodo, cargo, cargo_tipo, cargo_nota)
  values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 300, 'efectivo', 300, 'otro', 'Inventado') $$,
  '42501', null, 'El cobrador no puede cobrar cargos');
select throws_ok($$
  update prestamos set estado = 'pagado' where id = 'dddddddd-0000-0000-0000-000000000001' $$,
  null, 'El cobrador no puede dar por pagado un préstamo que no está cubierto');
select throws_ok($$
  update prestamos set monto = 1 where id = 'dddddddd-0000-0000-0000-000000000001' $$,
  null, 'El cobrador no puede cambiar el monto del préstamo');
delete from pagos;

reset role;
set local request.jwt.claims to '{}';
select is((select count(*)::int from pagos where descuento > 0 or anulado), 0,
  'El cobrador no puede meter descuentos ni cobros anulados');
select is((select count(*)::int from pagos), 3, 'El cobrador no puede borrar cobros');
select is((select monto from prestamos where id = 'dddddddd-0000-0000-0000-000000000001'),
  5000::numeric, 'El préstamo sigue con su monto');

-- Verificación en dos pasos ----------------------------------------------------
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
      and not exists (select 1 from pg_policies p
                       where p.schemaname = 'public' and p.tablename = c.relname
                         and p.policyname = 'dos_pasos')),
  0, 'Todas las tablas tienen la regla de dos pasos (si falla: correr el paso 2 de migracion_2026_11_02_dos_pasos.sql para la tabla nueva)');

-- A activa los dos pasos.
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
values (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000001', 'prueba', 'totp', 'verified', now(), now());

set local role authenticated;
set local request.jwt.claims to '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated","aal":"aal1"}';
select is((select count(*)::int from clientes), 0, 'Con dos pasos y sin el código, A no ve sus clientes');
select throws_ok($$
  insert into clientes (prestamista_id, nombre, cedula, telefono)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Sin código', '00100000009', '8099999999') $$,
  '42501', null, 'Con dos pasos y sin el código, A no puede crear clientes');

set local request.jwt.claims to '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated","aal":"aal2"}';
select is((select count(*)::int from clientes), 3, 'Con el código puesto, A ve sus clientes');

reset role;
set local request.jwt.claims to '{}';

select * from finish();
rollback;
