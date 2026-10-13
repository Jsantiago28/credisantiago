-- ==========================================================
-- MIGRACIÓN: límite a las fotos que se suben (12-10-2026)
-- ==========================================================
-- El link de solicitudes es público: cualquiera que lo tenga puede subir
-- fotos. Sin límite, alguien podría subir archivos enormes (o que no son
-- fotos) y llenar el 1 GB gratis de Supabase.
--
-- Desde ahora la carpeta de fotos solo acepta imágenes de hasta 10 MB
-- (lo mismo que ya pide la app en lib/widgets/elegir_foto.dart).
--
-- Se puede correr más de una vez sin problema.

update storage.buckets
   set file_size_limit = 10485760,                       -- 10 MB
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id = 'solicitudes-fotos';

-- Revisa que quedó: debe salir 10485760 y los tres tipos de imagen.
select id, public, file_size_limit, allowed_mime_types
  from storage.buckets
 where id = 'solicitudes-fotos';
