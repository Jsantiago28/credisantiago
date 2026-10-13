-- Contrato de préstamo (13-10-2026): el contrato se llena solo con los datos
-- del préstamo, del cliente y del prestamista. Del prestamista faltaban dos:
-- su cédula o RNC y la ciudad donde firma. Se ponen en Perfil → "Personalizar
-- mi recibo y contrato". Si están vacíos, el contrato trae una raya para
-- llenarlos a mano.
--
-- Las reglas que ya existen dejan que cada prestamista cambie solo su perfil.
--
-- Se puede correr más de una vez.

alter table profiles add column if not exists contrato_cedula text;   -- cédula o RNC del prestamista
alter table profiles add column if not exists contrato_ciudad text;   -- ej. Santo Domingo Este
