-- Precios nuevos (29-09-2026), para competir con PrestaCOP, Prestapp y PrestamosCloud.
-- Gratis: 10 clientes · Básico RD$390: 60 · Pro RD$690: 200 · Premium RD$1,190: sin límite.
-- Se puede correr más de una vez. Los límites los aplica la base de datos al instante.
insert into planes (id, nombre, precio_mensual, max_clientes, orden) values
  ('gratis',  'Gratis',  0,    10,   0),
  ('basico',  'Básico',  390,  60,   1),
  ('pro',     'Pro',     690,  200,  2),
  ('premium', 'Premium', 1190, null, 3)
on conflict (id) do update
  set nombre = excluded.nombre,
      precio_mensual = excluded.precio_mensual,
      max_clientes = excluded.max_clientes,
      orden = excluded.orden;
