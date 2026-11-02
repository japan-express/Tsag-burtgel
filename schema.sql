-- Supabase SQL Editor дээр нэг удаа ажиллуулна
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null,
  role text not null default 'employee' check (role in ('employee','admin'))
);
create table attendance (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  check_in timestamptz not null default now(),
  check_out timestamptz
);
-- Хүн бүрт зэрэг нэгээс олон нээлттэй бүртгэл байхгүй
create unique index one_open on attendance(user_id) where check_out is null;

alter table profiles enable row level security;
alter table attendance enable row level security;

create function is_admin() returns boolean
language sql security definer stable set search_path = public as
$$ select exists(select 1 from profiles where id = auth.uid() and role = 'admin') $$;

create policy "profiles read" on profiles for select using (id = auth.uid() or is_admin());
create policy "attendance read" on attendance for select using (user_id = auth.uid() or is_admin());
-- insert/update policy байхгүй: зөвхөн доорх функцээр бичигдэнэ

-- Ирлээ/Явлаа автоматаар сэлгэнэ (цагийг сервер өгнө, утасны цагаар хуурч болохгүй)
create function toggle_attendance() returns attendance
language plpgsql security definer set search_path = public as $$
declare r attendance;
begin
  update attendance set check_out = now()
    where user_id = auth.uid() and check_out is null returning * into r;
  if r.id is null then
    insert into attendance(user_id) values (auth.uid()) returning * into r;
  end if;
  return r;
end $$;
revoke all on function toggle_attendance() from public;
grant execute on function toggle_attendance() to authenticated;

-- Шинэ хэрэглэгч бүртгэгдэхэд profile автоматаар үүснэ
create function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, name) values (new.id, coalesce(new.raw_user_meta_data->>'name', new.email));
  return new;
end $$;
create trigger on_signup after insert on auth.users
  for each row execute function handle_new_user();

-- Өөрийгөө админ болгох (имэйлээ солиод ажиллуулна):
-- update profiles set role='admin' where id=(select id from auth.users where email='ta@example.mn');
