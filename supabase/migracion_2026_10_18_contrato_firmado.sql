-- Contrato firmado (18-10-2026).
--
-- En cada préstamo, el prestamista sube el contrato ya firmado (fotos de las
-- páginas o un PDF escaneado) para tenerlo a mano en un reclamo o demanda.
--
-- Va en la carpeta privada del prestamista en el bucket de fotos: por las
-- reglas que ya existen, SOLO él puede verlo (ni sus cobradores, ni otros
-- prestamistas, ni el admin). Aquí se guarda dónde está cada archivo.
--
-- Se puede correr más de una vez sin problema.

alter table prestamos add column if not exists contrato_firmado text[] not null default '{}';

-- La carpeta de fotos ahora también acepta PDF (hasta 10 MB, como las fotos).
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
 where id = 'solicitudes-fotos';

-- Revisa: deben salir los cuatro tipos.
select id, file_size_limit, allowed_mime_types from storage.buckets where id = 'solicitudes-fotos';
