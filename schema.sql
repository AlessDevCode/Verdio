-- =====================================================================
-- Verde Finanzas · Esquema completo para Supabase (PostgreSQL 15+)
-- Ejecutar en: Supabase Dashboard > SQL Editor
-- =====================================================================
create extension if not exists btree_gist;

create type period_kind        as enum ('monthly','biweekly','custom');
create type period_status      as enum ('open','closed');
create type expense_source     as enum ('period','fund');
create type fund_movement_type as enum ('remainder_in','replenishment_out');

-- ---------------------------------------------------------------------
-- TABLAS  (user_id siempre = auth.uid(); las FKs compuestas (id,user_id)
-- impiden referenciar filas de OTRO usuario aunque se conozca su UUID)
-- ---------------------------------------------------------------------
create table profiles (
  id            uuid primary key references auth.users on delete cascade,
  display_name  text,
  currency_code text not null default 'USD',
  created_at    timestamptz not null default now()
);

create table categories (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  name       text not null check (char_length(name) between 1 and 40),
  icon       text not null default 'category',
  color      text not null default '#2E7D32' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, name)
);

create table periods (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users on delete cascade,
  name              text not null check (char_length(name) between 1 and 60),
  kind              period_kind not null default 'monthly',
  start_date        date not null,
  end_date          date not null,
  budget            numeric(14,2) not null default 0 check (budget >= 0),
  status            period_status not null default 'open',
  closed_at         timestamptz,
  remainder_amount  numeric(14,2),
  remainder_sent_at timestamptz,
  created_at        timestamptz not null default now(),
  check (end_date >= start_date),
  unique (id, user_id),
  -- sin períodos solapados por usuario => asignación por fecha sin ambigüedad
  exclude using gist (user_id with =, daterange(start_date, end_date, '[]') with &&)
);

create table templates (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  name       text not null check (char_length(name) between 1 and 60),
  created_at timestamptz not null default now(),
  unique (id, user_id)
);

create table template_items (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users on delete cascade,
  template_id    uuid not null,
  category_id    uuid,
  name           text not null check (char_length(name) between 1 and 60),
  planned_amount numeric(14,2) not null default 0 check (planned_amount >= 0),
  created_at     timestamptz not null default now(),
  foreign key (template_id, user_id) references templates(id, user_id) on delete cascade,
  foreign key (category_id, user_id) references categories(id, user_id) on delete set null (category_id)
);

-- Partidas planificadas de un período (copiadas de una plantilla)
create table period_items (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users on delete cascade,
  period_id      uuid not null,
  category_id    uuid,
  name           text not null,
  planned_amount numeric(14,2) not null default 0 check (planned_amount >= 0),
  created_at     timestamptz not null default now(),
  unique (id, user_id),
  foreign key (period_id, user_id)   references periods(id, user_id)    on delete cascade,
  foreign key (category_id, user_id) references categories(id, user_id) on delete set null (category_id)
);

create table expenses (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users on delete cascade,
  source          expense_source not null default 'period',
  period_id       uuid,            -- null cuando source = 'fund'
  category_id     uuid,
  planned_item_id uuid,
  description     text not null default '' check (char_length(description) <= 140),
  amount          numeric(14,2) not null check (amount > 0),
  spent_on        date not null default current_date,
  created_at      timestamptz not null default now(),
  check ((source = 'fund' and period_id is null) or source = 'period'),
  foreign key (period_id, user_id)       references periods(id, user_id)      on delete cascade,
  foreign key (category_id, user_id)     references categories(id, user_id)   on delete set null (category_id),
  foreign key (planned_item_id, user_id) references period_items(id, user_id) on delete set null (planned_item_id)
);

-- Movimientos INTERNOS de la Caja General (no son gastos).
-- Solo se escriben mediante funciones RPC (sin políticas de escritura).
create table fund_movements (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users on delete cascade,
  type       fund_movement_type not null,
  amount     numeric(14,2) not null check (amount > 0),
  period_id  uuid not null,
  note       text,
  created_at timestamptz not null default now(),
  foreign key (period_id, user_id) references periods(id, user_id) on delete restrict
);
-- ANTI-DUPLICIDAD: un período solo puede enviar su remanente UNA vez.
create unique index fund_one_remainder_per_period
  on fund_movements (user_id, period_id) where type = 'remainder_in';

create index on expenses (user_id, spent_on);
create index on expenses (period_id);
create index on expenses (user_id) where source = 'fund';
create index on period_items (period_id);
create index on template_items (template_id);
create index on fund_movements (user_id, created_at desc);

-- ---------------------------------------------------------------------
-- VISTA de resumen por período (security_invoker => respeta RLS)
-- ---------------------------------------------------------------------
create view period_summary with (security_invoker = true) as
select p.*,
       coalesce(e.spent, 0)    as spent,
       coalesce(f.received, 0) as transfers_in
from periods p
left join (select period_id, sum(amount) spent
           from expenses where source = 'period' group by period_id) e on e.period_id = p.id
left join (select period_id, sum(amount) received
           from fund_movements where type = 'replenishment_out' group by period_id) f on f.period_id = p.id;

-- ---------------------------------------------------------------------
-- FUNCIONES INTERNAS
-- ---------------------------------------------------------------------
create function private_fund_balance(uid uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(case type when 'remainder_in' then amount else -amount end)
                   from fund_movements where user_id = uid), 0)
       - coalesce((select sum(amount) from expenses where user_id = uid and source = 'fund'), 0);
$$;
revoke all on function private_fund_balance(uuid) from public, anon, authenticated;

create function get_fund_balance() returns numeric
language sql stable security definer set search_path = public as $$
  select private_fund_balance(auth.uid());
$$;

-- Guardia de gastos: asigna período por fecha, bloquea períodos cerrados
-- y evita que la Caja General quede en negativo.
create function expenses_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare p periods%rowtype;
begin
  if tg_op = 'DELETE' then
    if old.period_id is not null and exists
       (select 1 from periods where id = old.period_id and status = 'closed') then
      raise exception 'El período está cerrado: no se pueden eliminar gastos';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and new.spent_on <> old.spent_on and new.source = 'period' then
    new.period_id := null;                      -- reasignar por la nueva fecha
  end if;

  if new.source = 'period' then
    if new.period_id is null then
      select * into p from periods
       where user_id = new.user_id and new.spent_on between start_date and end_date;
      if not found then
        raise exception 'No existe un período que contenga la fecha %', new.spent_on;
      end if;
      new.period_id := p.id;
    else
      select * into p from periods where id = new.period_id and user_id = new.user_id;
      if new.spent_on not between p.start_date and p.end_date then
        raise exception 'La fecha % queda fuera del período "%"', new.spent_on, p.name;
      end if;
    end if;
    if p.status = 'closed' then raise exception 'El período "%" está cerrado', p.name; end if;
  else
    perform pg_advisory_xact_lock(hashtext(new.user_id::text));
    if tg_op = 'INSERT' and private_fund_balance(new.user_id) < new.amount then
      raise exception 'Saldo insuficiente en la Caja General';
    end if;
  end if;
  return new;
end $$;
create trigger trg_expenses_guard before insert or update or delete on expenses
  for each row execute function expenses_guard();

-- Protege campos de cierre: solo modificables desde close_period / send_remainder_to_fund
create function periods_guard() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('app.allow_close', true), '') <> 'on' and (
       new.status            is distinct from old.status
    or new.closed_at         is distinct from old.closed_at
    or new.remainder_amount  is distinct from old.remainder_amount
    or new.remainder_sent_at is distinct from old.remainder_sent_at) then
    raise exception 'Operación no permitida: use close_period()';
  end if;
  if old.status = 'closed' and (new.budget <> old.budget
     or new.start_date <> old.start_date or new.end_date <> old.end_date) then
    raise exception 'Un período cerrado no puede modificarse';
  end if;
  return new;
end $$;
create trigger trg_periods_guard before update on periods
  for each row execute function periods_guard();

-- ---------------------------------------------------------------------
-- RPC de negocio
-- ---------------------------------------------------------------------
-- Crea período (+ partidas desde plantilla) de forma atómica. RLS aplica (invoker).
create function create_period(p_name text, p_kind period_kind, p_start date, p_end date,
                              p_budget numeric, p_template_id uuid default null)
returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into periods(name, kind, start_date, end_date, budget)
  values (trim(p_name), p_kind, p_start, p_end, p_budget) returning id into v_id;
  if p_template_id is not null then
    insert into period_items(period_id, category_id, name, planned_amount)
    select v_id, category_id, name, planned_amount
      from template_items where template_id = p_template_id;
  end if;
  return v_id;
end $$;

-- Envía el remanente a la Caja General (solo una vez por período).
create function send_remainder_to_fund(p_period_id uuid) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); s record; v_rem numeric;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  perform pg_advisory_xact_lock(hashtext(v_uid::text));
  select * into s from period_summary where id = p_period_id and user_id = v_uid;
  if not found then raise exception 'Período no encontrado'; end if;
  if s.status <> 'closed' then raise exception 'El período debe estar cerrado'; end if;
  if s.remainder_sent_at is not null then
    raise exception 'El remanente de este período ya fue enviado a la Caja General';
  end if;
  v_rem := s.budget + s.transfers_in - s.spent;
  if v_rem <= 0 then raise exception 'No hay remanente positivo para enviar'; end if;
  perform set_config('app.allow_close', 'on', true);
  insert into fund_movements(user_id, type, amount, period_id, note)
  values (v_uid, 'remainder_in', v_rem, p_period_id, 'Remanente de ' || s.name);
  update periods set remainder_sent_at = now() where id = p_period_id;
  return v_rem;
end $$;

create function close_period(p_period_id uuid, p_send_to_fund boolean default true) returns numeric
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); s record; v_rem numeric;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  perform pg_advisory_xact_lock(hashtext(v_uid::text));
  select * into s from period_summary where id = p_period_id and user_id = v_uid;
  if not found then raise exception 'Período no encontrado'; end if;
  if s.status = 'closed' then raise exception 'El período ya está cerrado'; end if;
  v_rem := s.budget + s.transfers_in - s.spent;
  perform set_config('app.allow_close', 'on', true);
  update periods set status = 'closed', closed_at = now(), remainder_amount = v_rem
   where id = p_period_id;
  if p_send_to_fund and v_rem > 0 then perform send_remainder_to_fund(p_period_id); end if;
  return v_rem;
end $$;

-- Transferencia de reposición Caja -> Período (movimiento interno, NO es gasto).
create function replenish_from_fund(p_period_id uuid, p_amount numeric, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_name text; v_status period_status;
begin
  if v_uid is null then raise exception 'No autenticado'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Monto inválido'; end if;
  perform pg_advisory_xact_lock(hashtext(v_uid::text));
  select name, status into v_name, v_status from periods where id = p_period_id and user_id = v_uid;
  if not found then raise exception 'Período no encontrado'; end if;
  if v_status <> 'open' then raise exception 'Solo se puede reponer un período abierto'; end if;
  if private_fund_balance(v_uid) < p_amount then raise exception 'Saldo insuficiente en la Caja General'; end if;
  insert into fund_movements(user_id, type, amount, period_id, note)
  values (v_uid, 'replenishment_out', p_amount, p_period_id, coalesce(p_note, 'Reposición a ' || v_name));
end $$;

revoke all on function close_period(uuid, boolean), send_remainder_to_fund(uuid),
  replenish_from_fund(uuid, numeric, text), get_fund_balance() from public, anon;
grant execute on function close_period(uuid, boolean), send_remainder_to_fund(uuid),
  replenish_from_fund(uuid, numeric, text), get_fund_balance() to authenticated;

-- Estadísticas anuales (las transferencias internas NO cuentan como gasto)
create function annual_monthly(p_year int)
returns table(month int, spent numeric, budget numeric)
language sql stable as $$
  select m,
    coalesce((select sum(e.amount) from expenses e
              where extract(year from e.spent_on) = p_year and extract(month from e.spent_on) = m), 0),
    coalesce((select sum(p.budget) from periods p
              where extract(year from p.start_date) = p_year and extract(month from p.start_date) = m), 0)
  from generate_series(1, 12) m
$$;

create function annual_by_category(p_year int)
returns table(name text, color text, icon text, total numeric)
language sql stable as $$
  select c.name, c.color, c.icon, sum(e.amount)
  from expenses e left join categories c on c.id = e.category_id
  where extract(year from e.spent_on) = p_year
  group by c.name, c.color, c.icon order by 4 desc
$$;

-- ---------------------------------------------------------------------
-- Alta de usuario: perfil + categorías por defecto
-- ---------------------------------------------------------------------
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)));
  insert into categories(user_id, name, icon, color) values
    (new.id, 'Alimentación', 'restaurant',     '#2E7D32'),
    (new.id, 'Transporte',   'directions_bus', '#00897B'),
    (new.id, 'Hogar',        'home',           '#558B2F'),
    (new.id, 'Servicios',    'receipt_long',   '#26A69A'),
    (new.id, 'Salud',        'health',         '#43A047'),
    (new.id, 'Educación',    'school',         '#1B5E20'),
    (new.id, 'Ocio',         'celebration',    '#66BB6A'),
    (new.id, 'Compras',      'shopping',       '#00695C'),
    (new.id, 'Otros',        'category',       '#78909C');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------
alter table profiles enable row level security;
create policy profiles_select on profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_update on profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

do $$
declare t text;
begin
  foreach t in array array['categories','periods','templates','template_items','period_items','expenses'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select to authenticated using ((select auth.uid()) = user_id)', t||'_select', t);
    execute format('create policy %I on %I for insert to authenticated with check ((select auth.uid()) = user_id)', t||'_insert', t);
    execute format('create policy %I on %I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t||'_update', t);
    execute format('create policy %I on %I for delete to authenticated using ((select auth.uid()) = user_id)', t||'_delete', t);
  end loop;
end $$;

-- Caja General: el cliente SOLO puede leer; escribir únicamente vía RPC.
alter table fund_movements enable row level security;
create policy fund_movements_select on fund_movements for select to authenticated
  using ((select auth.uid()) = user_id);
