-- ============================================================
-- Control de migraciones: cuáles ya se corrieron en la base de datos
-- ============================================================
-- GitHub (aplicar-migraciones.yml) corre solo las migraciones que no están
-- en esta lista, y las anota al terminar. Está en un esquema aparte que la
-- app no ve (no sale por la API).
--
-- Aquí se anotan todas las que ya se corrieron a mano hasta hoy (incluida
-- esta). Se puede correr más de una vez.

create schema if not exists control;
revoke all on schema control from public, anon, authenticated;

create table if not exists control.migraciones (
  nombre text primary key,
  aplicada_en timestamptz not null default now()
);
revoke all on control.migraciones from public, anon, authenticated;

insert into control.migraciones (nombre) values
  ('migracion_2026_09_22_monto_total.sql'),
  ('migracion_2026_09_23_anular_pagos.sql'),
  ('migracion_2026_09_23_cierres_caja.sql'),
  ('migracion_2026_09_23_mora.sql'),
  ('migracion_2026_09_23_planes.sql'),
  ('migracion_2026_09_23_recibos.sql'),
  ('migracion_2026_09_24_evidencias.sql'),
  ('migracion_2026_09_24_fotos_privadas.sql'),
  ('migracion_2026_09_24_gestiones.sql'),
  ('migracion_2026_09_24_historial_clientes.sql'),
  ('migracion_2026_09_24_ingresos_vivienda.sql'),
  ('migracion_2026_09_24_pagos_planes.sql'),
  ('migracion_2026_09_29_gastos.sql'),
  ('migracion_2026_09_29_precios_nuevos.sql'),
  ('migracion_2026_09_29_recibo_personalizado.sql'),
  ('migracion_2026_09_30_cobradores.sql'),
  ('migracion_2026_09_30_entregas.sql'),
  ('migracion_2026_10_12_limite_fotos.sql'),
  ('migracion_2026_10_13_contrato.sql'),
  ('migracion_2026_10_13_link_publico.sql'),
  ('migracion_2026_10_14_invitaciones.sql'),
  ('migracion_2026_10_14_registro.sql'),
  ('migracion_2026_10_17_interes_sobre_saldo.sql'),
  ('migracion_2026_10_17_logo_prestamista.sql'),
  ('migracion_2026_10_18_archivar_clientes.sql'),
  ('migracion_2026_10_18_contrato_firmado.sql'),
  ('migracion_2026_10_18_errores_y_gps.sql'),
  ('migracion_2026_10_18_legal_y_borrar_cuenta.sql'),
  ('migracion_2026_10_18_saldar_antes.sql'),
  ('migracion_2026_10_18_seguridad.sql'),
  ('migracion_2026_10_19_sin_conexion.sql'),
  ('migracion_2026_11_01_blindaje.sql'),
  ('migracion_2026_11_02_dos_pasos.sql'),
  ('migracion_2026_11_02_gracia.sql'),
  ('migracion_2026_11_02_indices.sql'),
  ('migracion_2026_11_02_pagado_sin_total.sql'),
  ('migracion_2026_11_02_reditos.sql'),
  ('migracion_2026_11_02_control_migraciones.sql')
on conflict (nombre) do nothing;
