-- Aab-e-Khizri v2.3 - advance payment (run ONCE in Supabase > SQL Editor)
-- Admin/user/customer checks reuse your existing aab_orders_list(), which returns NULL on bad credentials.

create table if not exists aab_pay_settings(
  id int primary key default 1 check (id=1),
  title text default '', acct text default '', bank text default '', adv int default 1000);
insert into aab_pay_settings(id) values(1) on conflict do nothing;

create table if not exists aab_advance(
  oid text primary key, txn text not null, amt int not null default 0, at timestamptz default now());

alter table aab_pay_settings enable row level security;
alter table aab_advance enable row level security;
revoke all on aab_pay_settings, aab_advance from anon, authenticated;

-- public: account details shown to customers while ordering
create or replace function aab_pay_cfg() returns json
language sql security definer set search_path=public as $$
  select json_build_object('title',title,'acct',acct,'bank',bank,'adv',adv) from aab_pay_settings where id=1 $$;

-- admin only: set account number / advance amount
create or replace function aab_set_pay(p_id text,p_h text,p_title text,p_acct text,p_bank text,p_adv int)
returns boolean language plpgsql security definer set search_path=public as $$
declare o jsonb;
begin
  o := aab_accounts_list(p_id=>p_id,p_h=>p_h)::jsonb;   -- admin-only list your app already uses
  if o is null or jsonb_typeof(o)<>'array' or jsonb_array_length(o)=0 then return false; end if;
  if p_adv is null or p_adv<0 or p_adv>1000000 then return false; end if;
  update aab_pay_settings set title=left(coalesce(p_title,''),80), acct=left(coalesce(p_acct,''),60),
         bank=left(coalesce(p_bank,''),60), adv=p_adv where id=1;
  return true;
end $$;

-- customer: attach the advance transaction ID to one of their own orders (once)
create or replace function aab_set_adv(p_id text,p_h text,p_oid text,p_txn text,p_amt int)
returns boolean language plpgsql security definer set search_path=public as $$
declare o jsonb; cap int;
begin
  o := aab_orders_list(p_role=>'customer',p_id=>p_id,p_h=>p_h)::jsonb;
  if o is null or jsonb_typeof(o)<>'array' then return false; end if;
  if not exists(select 1 from jsonb_array_elements(o) e where e->>'id'=p_oid) then return false; end if;
  if length(trim(coalesce(p_txn,'')))<4 or length(p_txn)>60 then return false; end if;
  select adv into cap from aab_pay_settings where id=1;
  insert into aab_advance(oid,txn,amt) values(p_oid,trim(p_txn),least(greatest(coalesce(p_amt,0),0),coalesce(cap,0)))
  on conflict (oid) do nothing;
  return true;
end $$;

-- admin/user see all advances, customer sees only their own orders' advances
create or replace function aab_adv_list(p_role text,p_id text,p_h text) returns json
language plpgsql security definer set search_path=public as $$
declare o jsonb;
begin
  o := aab_orders_list(p_role=>p_role,p_id=>p_id,p_h=>p_h)::jsonb;
  if o is null or jsonb_typeof(o)='null' then return null; end if;
  return coalesce((select json_agg(json_build_object('oid',a.oid,'txn',a.txn,'amt',a.amt))
    from aab_advance a
    where p_role in ('admin','user')
       or exists(select 1 from jsonb_array_elements(o) e where e->>'id'=a.oid)),'[]'::json);
end $$;

-- make the API see the new functions immediately
notify pgrst, 'reload schema';
