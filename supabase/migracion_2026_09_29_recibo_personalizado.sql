-- Recibo personalizado (29-09-2026): cada prestamista pone en su recibo su
-- logo, teléfono, dirección y un mensaje al pie. El nombre del negocio ya
-- existía (profiles.negocio). Todo es opcional: si está vacío, el recibo
-- sale como antes.
--
-- El logo va en el mismo bucket privado de las fotos, en la carpeta del
-- prestamista (así lo protegen las reglas que ya existen), y aquí se guarda
-- su ubicación.
--
-- Se puede correr más de una vez.

alter table profiles add column if not exists recibo_logo text;       -- ej. <prestamista>/logo_....jpg
alter table profiles add column if not exists recibo_telefono text;   -- si está vacío: su WhatsApp
alter table profiles add column if not exists recibo_direccion text;
alter table profiles add column if not exists recibo_mensaje text;    -- si está vacío: "Gracias por su pago."
