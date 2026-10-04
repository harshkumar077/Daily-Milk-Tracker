-- Daily Milk Tracker: run this in the Supabase SQL editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  email text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  created_at timestamptz not null default now(),
  unique (family_id, user_id)
);

create table if not exists public.milk_records (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  date date not null,
  quantity_litres numeric(8, 2) not null check (quantity_litres > 0 and quantity_litres <= 100),
  price_per_litre numeric(10, 2) not null check (price_per_litre >= 0),
  note text not null default '',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (family_id, date)
);

create table if not exists public.family_settings (
  family_id uuid primary key references public.families(id) on delete cascade,
  default_price numeric(10, 2) not null default 60 check (default_price >= 0),
  quick_quantities jsonb not null default '[0.5, 1, 1.25, 1.5, 1.75, 2, 2.5]'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists milk_records_family_date_idx on public.milk_records (family_id, date);
create index if not exists family_members_user_idx on public.family_members (user_id);

create or replace function public.is_family_member(target_family uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.family_members where family_id = target_family and user_id = auth.uid());
$$;

create or replace function public.is_family_admin(target_family uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.family_members where family_id = target_family and user_id = auth.uid() and role = 'admin');
$$;

alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.milk_records enable row level security;
alter table public.family_settings enable row level security;

drop policy if exists profiles_self on public.profiles;
create policy profiles_self on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists families_member_read on public.families;
create policy families_member_read on public.families for select using (public.is_family_member(id));
drop policy if exists families_creator_read on public.families;
create policy families_creator_read on public.families for select using (created_by = auth.uid());
drop policy if exists families_create on public.families;
create policy families_create on public.families for insert with check (created_by = auth.uid());
drop policy if exists families_admin_update on public.families;
create policy families_admin_update on public.families for update using (public.is_family_admin(id));

drop policy if exists family_members_read on public.family_members;
create policy family_members_read on public.family_members for select using (public.is_family_member(family_id));
drop policy if exists family_members_join on public.family_members;
create policy family_members_join on public.family_members for insert with check (user_id = auth.uid());
drop policy if exists family_members_admin_update on public.family_members;
create policy family_members_admin_update on public.family_members for update using (public.is_family_admin(family_id));
drop policy if exists family_members_self_delete on public.family_members;
create policy family_members_self_delete on public.family_members for delete using (user_id = auth.uid() or public.is_family_admin(family_id));

create policy milk_records_member_read on public.milk_records for select using (public.is_family_member(family_id));
create policy milk_records_member_insert on public.milk_records for insert with check (public.is_family_member(family_id) and created_by = auth.uid() and date <= current_date);
create policy milk_records_member_update on public.milk_records for update using (public.is_family_member(family_id)) with check (public.is_family_member(family_id) and date <= current_date);
create policy milk_records_member_delete on public.milk_records for delete using (public.is_family_member(family_id));

create policy family_settings_member_read on public.family_settings for select using (public.is_family_member(family_id));
create policy family_settings_admin_write on public.family_settings for all using (public.is_family_admin(family_id)) with check (public.is_family_admin(family_id));

-- Invite-code lookup and membership creation happen atomically on the server.
create or replace function public.join_family_by_code(requested_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare target_family uuid;
begin
  select id into target_family from public.families where invite_code = upper(trim(requested_code));
  if target_family is null then return null; end if;
  insert into public.family_members (family_id, user_id, role)
    values (target_family, auth.uid(), 'member')
    on conflict (family_id, user_id) do nothing;
  return target_family;
end;
$$;
revoke all on function public.join_family_by_code(text) from public;
grant execute on function public.join_family_by_code(text) to authenticated;

-- Keep profiles in sync for new signups. The app also upserts profiles after login.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email) values (new.id, coalesce(new.raw_user_meta_data->>'name', ''), coalesce(new.email, ''));
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
