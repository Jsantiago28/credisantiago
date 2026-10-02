-- ==========================================================
-- MIGRACIÓN: historial de cambios del cliente
-- ==========================================================
-- Correr en Supabase (SQL Editor). Desde ese momento, cada vez que se
-- cambia un dato de un cliente (nombre, cédula, teléfono, fotos,
-- ubicación, referencias...) queda anotado: qué dato, lo que decía
-- antes, lo que dice ahora, quién y cuándo.
--
-- Lo anota la base de datos (trigger), así que ningún cambio se salta el
-- historial, venga de donde venga. El historial no se edita ni se borra.
-- Los cambios hechos antes de correr esto no quedan registrados.
-- Se puede correr más de una vez sin problema.

create table if not exists clientes_historial (
  id uuid primary key default uuid_generate_v4(),
  prestamista_id uuid references profiles(id) on delete cascade,
  cliente_id uuid not null references clientes(id) on delete cascade,
  campo text not null,          -- ej. 'telefono', 'foto_cara_url'
  antes text,                   -- lo que decía (null = vacío)
  despues text,                 -- lo que dice ahora
  hecho_por uuid,               -- quién lo cambió (null = desde el SQL Editor)
  created_at timestamptz default now()
);

create index if not exists idx_clientes_historial_cliente on clientes_historial(cliente_id);

alter table clientes_historial enable row level security;

-- El prestamista solo puede VER el historial de sus clientes. Nadie puede
-- escribirlo, cambiarlo ni borrarlo a mano: solo el trigger de abajo.
drop policy if exists "clientes_historial_select_own" on clientes_historial;
create policy "clientes_historial_select_own" on clientes_historial
  for select using (auth.uid() = prestamista_id);

-- Compara la fila vieja con la nueva y anota cada dato que cambió. Todos
-- los datos cambiados en un mismo "Guardar" quedan con la misma hora.
create or replace function registrar_cambios_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  viejo jsonb := to_jsonb(old);
  nuevo jsonb := to_jsonb(new);
  campo text;
begin
  for campo in select jsonb_object_keys(nuevo) loop
    if campo in ('id', 'prestamista_id', 'solicitud_id', 'created_at') then
      continue;
    end if;
    if (viejo -> campo) is distinct from (nuevo -> campo) then
      insert into clientes_historial
        (prestamista_id, cliente_id, campo, antes, despues, hecho_por)
      values
        (new.prestamista_id, new.id, campo, viejo ->> campo, nuevo ->> campo, auth.uid());
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_historial_clientes on clientes;
create trigger trg_historial_clientes
  after update on clientes
  for each row execute function registrar_cambios_cliente();
