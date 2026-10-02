-- ==========================================================
-- MIGRACIÓN: ingreso mensual y tipo de vivienda
-- ==========================================================
-- Correr en Supabase (SQL Editor) ANTES de usar la versión de la app que
-- pregunta "¿casa propia o alquilada?": esa versión guarda estas columnas
-- al enviar una solicitud, al aprobarla y al crear un cliente a mano. Sin
-- ellas, esas tres cosas fallan.
--
-- tipo_vivienda: 'propia' o 'alquilada'.
-- clientes.ingreso_mensual: cuánto gana al mes. Antes solo quedaba en la
--   solicitud; ahora se copia al cliente (y se pide al crearlo a mano).
--
-- Las columnas de ingresos de solicitudes ya existían en tu base de datos
-- (el formulario las usa); se repiten con "if not exists" para que este
-- archivo sirva también en una base nueva.

alter table solicitudes add column if not exists ingreso_mensual numeric(12,2);
alter table solicitudes add column if not exists tiene_otros_ingresos boolean default false;
alter table solicitudes add column if not exists otros_ingresos_descripcion text;
alter table solicitudes add column if not exists otros_ingresos_monto numeric(12,2);
alter table solicitudes add column if not exists frecuencia_pago text;
alter table solicitudes add column if not exists capacidad_pago numeric(12,2);
alter table solicitudes add column if not exists tipo_vivienda text
  check (tipo_vivienda in ('propia', 'alquilada'));

-- Los clientes existentes toman el ingreso de su solicitud.
alter table clientes add column if not exists ingreso_mensual numeric(12,2);
alter table clientes add column if not exists tipo_vivienda text
  check (tipo_vivienda in ('propia', 'alquilada'));

update clientes c
set ingreso_mensual = s.ingreso_mensual
from solicitudes s
where c.solicitud_id = s.id and c.ingreso_mensual is null;
