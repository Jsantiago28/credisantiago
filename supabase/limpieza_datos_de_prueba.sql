-- Limpieza de datos de prueba (18-10-2026) — NO es una migración.
--
-- Úsalo en Supabase → SQL Editor, PASO POR PASO. Los pasos 1 a 3 solo
-- MUESTRAN; nada se borra hasta el paso 4, y solo lo que tú elijas.
-- Antes de borrar, asegúrate de tener la copia de seguridad del domingo.

-- 1. Préstamos sin cronograma (de las primeras pruebas): nunca salen
--    atrasados ni cobran mora. ------------------------------------------------
select p.id as prestamo_id, c.nombre as cliente, c.cedula, p.monto, p.estado,
       p.created_at::date as creado,
       (select count(*) from pagos g where g.prestamo_id = p.id and not g.anulado) as cobros
  from prestamos p
  join clientes c on c.id = p.cliente_id
 where p.estado in ('en_calle', 'borrador')
   and (p.cantidad_cuotas is null or p.cuota is null or p.fecha_desembolso is null)
 order by p.created_at;

-- 2. Cédulas repetidas: el mismo número en más de un cliente o solicitud. -----
select 'cliente' as donde, cedula, nombre, created_at::date as creado
  from clientes
 where regexp_replace(cedula, '\D', '', 'g') in (
   select regexp_replace(cedula, '\D', '', 'g') from clientes group by 1 having count(*) > 1)
union all
select 'solicitud', s.cedula, s.nombre, s.created_at::date
  from solicitudes s
 where s.estado = 'nueva'
   and regexp_replace(s.cedula, '\D', '', 'g') in (
     select regexp_replace(cedula, '\D', '', 'g') from clientes)
 order by cedula;

-- 3. Clientes con nombres o cédulas de prueba (aaa, qqqq, test, 000...). ------
select id as cliente_id, nombre, cedula, telefono, created_at::date as creado
  from clientes
 where nombre ~* '^(a+|q+|x+|test|prueba|john|aquiles)\M'
    or regexp_replace(cedula, '\D', '', 'g') !~ '^\d{11}$'
 order by created_at;

-- 4. BORRAR lo que elijas. Copia los id de arriba, quita los dos guiones (--)
--    de la línea que necesites y córrela. Al borrar un cliente se borran sus
--    préstamos y cobros.
--
-- delete from clientes where id in ('PEGA-AQUI-EL-ID', 'OTRO-ID');
-- delete from solicitudes where id in ('PEGA-AQUI-EL-ID');
-- update prestamos set estado = 'cancelado' where id in ('PEGA-AQUI-EL-ID');  -- en vez de borrar
