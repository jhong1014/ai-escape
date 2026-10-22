-- AI 연구소 탈출 — 수퍼베이스 서버 함수
-- 수퍼베이스 대시보드 → SQL Editor 에 전체를 붙여 넣고 [Run] 하세요. (한 번만 실행)
-- 테이블(escape_schools, escape_settings, escape_students, escape_records)은 이미 만들어져 있어요.

create extension if not exists pgcrypto with schema extensions;

-- 1) 학교 표시 순서
alter table public.escape_schools add column if not exists sort_order int not null default 0;
update public.escape_schools set sort_order = case name
  when '장성중학교' then 1 when '장성삼서중학교' then 2 when '장성황룡중학교' then 3 else 99 end
  where sort_order = 0;

-- 2) 관리자 비밀번호 — 학생이 읽을 수 없는 별도 테이블에 암호화해서 저장 (처음 값 1234)
create table if not exists public.escape_admin (
  id int primary key default 1 check (id = 1),
  pw_hash text not null
);
comment on table public.escape_admin is 'AI 연구소 탈출 - 관리자 비밀번호(해시). 처음 값 1234';
alter table public.escape_admin enable row level security;
insert into public.escape_admin (id, pw_hash)
  values (1, extensions.crypt('1234', extensions.gen_salt('bf')))
  on conflict (id) do nothing;

-- 3) 기록 저장은 아래 escape_submit 함수로만 (학번·회차를 서버에서 계산)
drop policy if exists "public insert" on public.escape_records;

-- 4) 학교 목록 저장 시(전체 다시 쓰기) 학생명단이 막지 않도록
alter table public.escape_students drop constraint if exists escape_students_school_fkey;

create or replace function public.escape_check_pw(pw text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(pw, '') <> '' and exists (
    select 1 from public.escape_admin a where a.pw_hash = extensions.crypt(pw, a.pw_hash));
$$;

-- 탈출 기록 저장 (기존 Code.gs 의 submit_ 과 같은 규칙)
create or replace function public.escape_submit(rec jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ban int := nullif(regexp_replace(coalesce(rec->>'ban',''), '\D', '', 'g'), '')::int;
  v_num int := nullif(regexp_replace(coalesce(rec->>'num',''), '\D', '', 'g'), '')::int;
  v_grade int := coalesce(nullif(nullif(regexp_replace(coalesce(rec->>'grade',''), '\D', '', 'g'), '')::int, 0), 2);
  v_name text := left(btrim(regexp_replace(coalesce(rec->>'name',''), '[\r\n\t]', ' ', 'g')), 20);
  v_school text := left(btrim(regexp_replace(coalesce(rec->>'school',''), '[\r\n\t]', ' ', 'g')), 40);
  v_start bigint := coalesce(nullif(rec->>'startedAt','')::numeric, 0)::bigint;
  v_fin bigint := coalesce(nullif(rec->>'finishedAt','')::numeric, 0)::bigint;
  v_now bigint := (extract(epoch from now()) * 1000)::bigint;
  v_elapsed int; v_hak text; v_id text; v_tries int;
begin
  if not (coalesce(v_ban,0) > 0 and coalesce(v_num,0) > 0 and v_name <> '' and v_start > 0 and v_fin > v_start) then
    return jsonb_build_object('ok', false, 'error', 'bad_record');
  end if;
  -- 학생 기기 시계가 조금 틀려도 되도록: 하루 안의 기록, 6시간 이내 플레이만
  if abs(v_now - v_fin) > 24*3600*1000 or v_fin - v_start > 6*3600*1000 then
    return jsonb_build_object('ok', false, 'error', 'bad_time');
  end if;
  v_elapsed := round((v_fin - v_start) / 1000.0);
  v_hak := v_grade::text || lpad(v_ban::text, 2, '0') || lpad(v_num::text, 2, '0');
  v_id := v_start::text || '-' || v_hak;
  perform pg_advisory_xact_lock(hashtext('escape:' || v_school || ':' || v_hak));
  if exists (select 1 from public.escape_records where record_id = v_id) then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;
  select count(*) into v_tries from public.escape_records
    where student_no = v_hak::int and school = v_school;
  insert into public.escape_records (record_id, saved_at, school, grade, class_no, number, student_no, name,
    elapsed_text, elapsed_sec, wrong_count, hint_count, rank_title, started_at, escaped_at, start_ms, escape_ms, attempt)
  values (v_id, now(), v_school, v_grade, v_ban, v_num, v_hak::int, v_name,
    (v_elapsed / 60)::text || '분 ' || lpad((v_elapsed % 60)::text, 2, '0') || '초', v_elapsed,
    coalesce(nullif(regexp_replace(coalesce(rec->>'wrong',''), '\D', '', 'g'), '')::int, 0),
    coalesce(nullif(regexp_replace(coalesce(rec->>'hints',''), '\D', '', 'g'), '')::int, 0),
    left(btrim(coalesce(rec->>'rank','')), 20),
    to_timestamp(v_start / 1000.0), to_timestamp(v_fin / 1000.0), v_start, v_fin, v_tries + 1);
  return jsonb_build_object('ok', true, 'id', v_id, 'attempt', v_tries + 1);
end $$;

create or replace function public.escape_admin_login(pw text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when public.escape_check_pw(pw) then jsonb_build_object('ok', true)
              else jsonb_build_object('ok', false, 'error', 'bad_password') end;
$$;

create or replace function public.escape_save_config(pw text, schools text[], new_pw text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n int := 0; s text; seen text[] := '{}';
begin
  if not public.escape_check_pw(pw) then return jsonb_build_object('ok', false, 'error', 'bad_password'); end if;
  if coalesce(new_pw, '') <> '' and length(new_pw) < 4 then return jsonb_build_object('ok', false, 'error', 'short_password'); end if;
  delete from public.escape_schools where true;
  foreach s in array coalesce(schools, '{}') loop
    s := left(btrim(regexp_replace(coalesce(s, ''), '\s+', ' ', 'g')), 40);
    if s <> '' and not (s = any(seen)) then
      n := n + 1; seen := seen || s;
      insert into public.escape_schools (name, sort_order) values (s, n);
    end if;
  end loop;
  if coalesce(new_pw, '') <> '' then
    update public.escape_admin set pw_hash = extensions.crypt(new_pw, extensions.gen_salt('bf')) where id = 1;
  end if;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

create or replace function public.escape_delete_result(pw text, id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.escape_check_pw(pw) then return jsonb_build_object('ok', false, 'error', 'bad_password'); end if;
  delete from public.escape_records where record_id = id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.escape_clear_results(pw text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not public.escape_check_pw(pw) then return jsonb_build_object('ok', false, 'error', 'bad_password'); end if;
  delete from public.escape_records where true;
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.escape_check_pw(text) from public, anon, authenticated;
grant execute on function public.escape_submit(jsonb), public.escape_admin_login(text),
  public.escape_save_config(text, text[], text), public.escape_delete_result(text, text),
  public.escape_clear_results(text) to anon, authenticated;
