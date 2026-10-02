-- ==========================================================
-- PRESTAMISTAS RD APP PRO - SCHEMA SUPABASE (FASE 1 MVP)
-- ==========================================================

-- Extensión para UUID
create extension if not exists "uuid-ossp";

-- ----------------------------------------------------------
-- 1. PROFILES (prestamistas)
-- ----------------------------------------------------------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  phone text unique not null,
  nombre text,
  slug text unique not null, -- ej: juan-prestamos
  negocio text,
  exigir_evidencias boolean not null default false, -- su link exige evidencia de ingresos
  created_at timestamptz default now()
);

-- ----------------------------------------------------------
-- 2. SOLICITUDES (formulario público, sin login)
-- ----------------------------------------------------------
create table if not exists solicitudes (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid references profiles(id) on delete cascade,

  -- Paso 1: fotos
  foto_cara_url text,
  foto_cedula_frente_url text,
  foto_cedula_reverso_url text,

  -- Paso 2: datos personales
  nombre text not null,
  cedula text not null,
  telefono text not null,
  direccion text,
  lat double precision,
  lng double precision,

  -- Paso 3: trabajo
  trabajo_lugar text,
  trabajo_direccion text,
  jefe_nombre text,
  jefe_telefono text,                 -- "jefe" = supervisor o Recursos Humanos
  ingreso_mensual numeric(12,2),
  tiene_otros_ingresos boolean default false,
  otros_ingresos_descripcion text,
  otros_ingresos_monto numeric(12,2),
  tipo_vivienda text check (tipo_vivienda in ('propia','alquilada')),
  frecuencia_pago text,
  capacidad_pago numeric(12,2),
  evidencias_ingresos text[] not null default '{}', -- fotos: volante, carta de trabajo...

  -- Paso 4: referencias (2)
  ref1_nombre text,
  ref1_parentesco text,
  ref1_telefono text,
  ref2_nombre text,
  ref2_parentesco text,
  ref2_telefono text,

  -- Paso 5: cobro (opcional)
  metodo_cobro text check (metodo_cobro in ('transferencia','billetera','efectivo','sin_definir')) default 'sin_definir',
  banco text check (banco in ('Banreservas','Popular','BHD','Scotia','Otro',null)),
  numero_cuenta text,
  billetera text check (billetera in ('Qik','MIO',null)),

  -- Monto solicitado (si aplica)
  monto_solicitado numeric(12,2),

  -- Estado del flujo
  estado text check (estado in ('nueva','aprobada','rechazada')) default 'nueva',

  -- Auditoría
  ip_address text,
  created_at timestamptz default now()
);

create index if not exists idx_solicitudes_prestamista on solicitudes(prestamista_id);
create index if not exists idx_solicitudes_estado on solicitudes(estado);

-- ----------------------------------------------------------
-- 3. CLIENTES (creados al aprobar una solicitud)
-- ----------------------------------------------------------
create table if not exists clientes (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid references profiles(id) on delete cascade,
  solicitud_id uuid references solicitudes(id),

  nombre text not null,
  cedula text not null,
  telefono text not null,
  direccion text,
  lat double precision,
  lng double precision,

  foto_cara_url text,
  foto_cedula_frente_url text,
  foto_cedula_reverso_url text,

  trabajo_lugar text,
  trabajo_direccion text,
  jefe_nombre text,
  jefe_telefono text,
  ingreso_mensual numeric(12,2),
  tipo_vivienda text check (tipo_vivienda in ('propia','alquilada')),
  evidencias_ingresos text[] not null default '{}',

  ref1_nombre text,
  ref1_parentesco text,
  ref1_telefono text,
  ref2_nombre text,
  ref2_parentesco text,
  ref2_telefono text,

  metodo_cobro text,
  banco text,
  numero_cuenta text,
  billetera text,

  created_at timestamptz default now()
);

create index if not exists idx_clientes_prestamista on clientes(prestamista_id);

-- ----------------------------------------------------------
-- 4. PRESTAMOS
-- ----------------------------------------------------------
create table if not exists prestamos (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid references profiles(id) on delete cascade,
  cliente_id uuid references clientes(id) on delete cascade,

  monto numeric(12,2) not null,
  tasa_interes numeric(5,2) default 0, -- % MENSUAL, escalado según el plazo
  cuota numeric(12,2),              -- cuota normal (pesos enteros)
  cantidad_cuotas int,
  monto_total numeric(12,2),        -- total a devolver; la última cuota absorbe el redondeo
  mora_diaria numeric(5,2) not null default 0, -- % diario sobre lo que falta de la cuota vencida
  dias_gracia int not null default 1,          -- días después del vencimiento sin recargo
  frecuencia text check (frecuencia in ('diario','semanal','quincenal','mensual')) default 'semanal',
  fecha_desembolso date,
  proximo_pago date,

  estado text check (estado in ('borrador','en_calle','por_cobrar','atrasado','pagado','cancelado')) default 'borrador',

  created_at timestamptz default now()
);

create index if not exists idx_prestamos_prestamista on prestamos(prestamista_id);
create index if not exists idx_prestamos_estado on prestamos(estado);
create index if not exists idx_prestamos_cliente on prestamos(cliente_id);

-- ----------------------------------------------------------
-- 5. PAGOS
-- ----------------------------------------------------------
create table if not exists pagos (
  id uuid primary key default uuid_generate_v4(),
  prestamo_id uuid references prestamos(id) on delete cascade,
  prestamista_id uuid references profiles(id) on delete cascade,

  monto numeric(12,2) not null,
  monto_mora numeric(12,2) not null default 0, -- parte del cobro que fue a mora
  numero_recibo int, -- consecutivo por prestamista (trigger, ver migracion_2026_09_23_recibos.sql)
  anulado boolean not null default false, -- cobro mal digitado: no cuenta, pero no se borra
  anulado_en timestamptz,
  motivo_anulacion text,
  fecha_pago timestamptz default now(),
  metodo text,

  created_at timestamptz default now()
);

create index if not exists idx_pagos_prestamo on pagos(prestamo_id);
create index if not exists idx_pagos_prestamista on pagos(prestamista_id);

-- ----------------------------------------------------------
-- 6. CIERRES DE CAJA (resumen de un día, lo borra el prestamista)
--    Ver migracion_2026_09_23_cierres_caja.sql (tabla + RLS).
-- ----------------------------------------------------------
create table if not exists cierres_caja (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  fecha date not null,
  total numeric(12,2) not null,
  cuotas numeric(12,2) not null,
  mora numeric(12,2) not null,
  cantidad_cobros int not null,
  nota text,
  created_at timestamptz default now(),
  unique (prestamista_id, fecha)
);

-- ----------------------------------------------------------
-- 7. GESTIONES Y ACUERDOS DE COBRO (visitas, llamadas, promesas)
--    Ver migracion_2026_09_24_gestiones.sql (tabla + RLS, sin update
--    ni delete: quedan como historial).
-- ----------------------------------------------------------
create table if not exists gestiones (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid not null references profiles(id) on delete cascade,
  prestamo_id uuid not null references prestamos(id) on delete cascade,
  cliente_id uuid references clientes(id) on delete cascade,
  tipo text not null check (tipo in ('visita', 'llamada', 'whatsapp', 'otro')),
  resultado text not null
    check (resultado in ('pago', 'promesa', 'no_estaba', 'se_nego', 'otro')),
  acuerdo text,
  promesa_fecha date,
  promesa_monto numeric(12,2),
  hecho_por uuid default auth.uid(),
  created_at timestamptz default now()
);

-- ----------------------------------------------------------
-- 8. HISTORIAL DE CAMBIOS DEL CLIENTE (lo llena un trigger)
--    Ver migracion_2026_09_24_historial_clientes.sql (tabla, RLS de
--    solo lectura y el trigger registrar_cambios_cliente).
-- ----------------------------------------------------------
create table if not exists clientes_historial (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid references profiles(id) on delete cascade,
  cliente_id uuid not null references clientes(id) on delete cascade,
  campo text not null,
  antes text,
  despues text,
  hecho_por uuid,
  created_at timestamptz default now()
);

-- ==========================================================
-- ROW LEVEL SECURITY
-- ==========================================================
alter table profiles enable row level security;
alter table solicitudes enable row level security;
alter table clientes enable row level security;
alter table prestamos enable row level security;
alter table pagos enable row level security;

-- PROFILES: cada prestamista ve/edita solo su propio perfil
create policy "profiles_select_own" on profiles for select using (auth.uid() = id);
create policy "profiles_update_own" on profiles for update using (auth.uid() = id);
create policy "profiles_insert_own" on profiles for insert with check (auth.uid() = id);

-- SOLICITUDES:
-- Insert público (el cliente anónimo llena el formulario sin login)
create policy "solicitudes_insert_public" on solicitudes for insert with check (true);
-- Select solo el prestamista dueño
create policy "solicitudes_select_own" on solicitudes for select using (auth.uid() = prestamista_id);
create policy "solicitudes_update_own" on solicitudes for update using (auth.uid() = prestamista_id);

-- CLIENTES / PRESTAMOS / PAGOS: solo el prestamista dueño
create policy "clientes_all_own" on clientes for all using (auth.uid() = prestamista_id);
create policy "prestamos_all_own" on prestamos for all using (auth.uid() = prestamista_id);
create policy "pagos_all_own" on pagos for all using (auth.uid() = prestamista_id);

-- ==========================================================
-- REALTIME (para el badge de "Solicitudes Nuevas")
-- ==========================================================
alter publication supabase_realtime add table solicitudes;
alter publication supabase_realtime add table prestamos;
alter publication supabase_realtime add table pagos;

-- ==========================================================
-- STORAGE BUCKETS (crear también desde el dashboard de Supabase)
-- ==========================================================
-- bucket: "solicitudes-fotos" (público para insert, privado para read)
-- Ejecutar en el dashboard de Storage o vía SQL si tienes extensión storage habilitada.
