-- ==========================================================
-- MIGRACIÓN: evidencias de ingresos
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de usar la versión de la app con
-- "Evidencias de ingresos": esa versión guarda estas columnas al enviar
-- una solicitud, al aprobarla, al crear un cliente a mano y al cambiar el
-- interruptor del Perfil. Sin ellas, esas cosas fallan.
--
-- evidencias_ingresos: enlaces a las fotos (volante de pago, carta de
--   trabajo, estado de cuenta...), en el mismo bucket que las fotos de la
--   cédula. Al aprobar la solicitud se copian al cliente.
-- profiles.exigir_evidencias: si el prestamista la exige, su link no deja
--   enviar la solicitud sin al menos una foto.

alter table solicitudes add column if not exists evidencias_ingresos text[] not null default '{}';
alter table clientes add column if not exists evidencias_ingresos text[] not null default '{}';
alter table profiles add column if not exists exigir_evidencias boolean not null default false;
