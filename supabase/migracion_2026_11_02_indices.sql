-- Índices para que las pantallas carguen rápido (02-11-2026), según la
-- revisión de rendimiento. Solo agrega índices: no cambia datos ni permisos.
-- Se puede correr varias veces (if not exists).
--
--  1. Cobros por prestamista y fecha: la Caja (un año de cobros) y las
--     gráficas de Reportes piden "cobros de este prestamista desde tal día,
--     ordenados por fecha".
--  2. Préstamos por prestamista y estado: Inicio pide los "en la calle" y
--     Reportes los en la calle, pagados y atrasados.
--  3. Solicitudes por prestamista y estado: la barra de abajo cuenta las
--     nuevas cada vez que cambia una.
--
-- Ya existían (no se repiten): clientes(prestamista_id) en schema.sql y
-- gestiones(prestamo_id) en migracion_2026_09_24_gestiones.sql.

create index if not exists idx_pagos_prestamista_fecha
  on pagos (prestamista_id, fecha_pago);

create index if not exists idx_prestamos_prestamista_estado
  on prestamos (prestamista_id, estado);

create index if not exists idx_solicitudes_prestamista_estado
  on solicitudes (prestamista_id, estado);

-- Por si una base vieja no los tiene (también están en schema.sql y en la
-- migración de gestiones).
create index if not exists idx_clientes_prestamista on clientes (prestamista_id);
create index if not exists idx_gestiones_prestamo on gestiones (prestamo_id);
