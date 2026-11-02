-- ============================================================
-- Borra el NEGOCIO DE DEMOSTRACIÓN (tool/negocio_demo.dart)
-- ============================================================
-- Todo lo de la demo tiene ids que empiezan con "de300000". Lo demás de la
-- cuenta no se toca. NO es una migración (no se aplica sola): se corre a
-- mano cuando se quiera quitar la demo.

begin;
set local request.jwt.claims to '{}';

delete from gestiones where prestamo_id::text like 'de300000%';
delete from entregas_cobrador where cobrador_id::text like 'de300000%';
delete from pagos where id::text like 'de300000%';
delete from prestamos where id::text like 'de300000%';
delete from clientes_historial where cliente_id::text like 'de300000%';
delete from clientes where id::text like 'de300000%';
delete from cierres_caja where id::text like 'de300000%';
delete from gastos where id::text like 'de300000%';
delete from solicitudes where id::text like 'de300000%';
delete from cobradores where id::text like 'de300000%';
delete from auth.identities where user_id::text like 'de300000%';
delete from auth.users where id::text like 'de300000%';

commit;
