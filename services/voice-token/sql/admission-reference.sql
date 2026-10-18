-- DEPLOYMENT REFERENCE ONLY. Not applied, and not a Supabase migration record.
-- Review in the selected FEEL project, apply as its database owner, then run the
-- verification/concurrency checks in README.md before enabling production mode.
begin;
create schema if not exists feel_admission;
revoke all on schema feel_admission from public, anon, authenticated;
grant usage on schema feel_admission to service_role;

create table if not exists feel_admission.policies (
    operation text primary key check (operation in
        ('voice_session', 'context_last_seen', 'context_room_structure', 'context_room_anchors')),
    enabled boolean not null default false,
    per_user_minute integer not null check (per_user_minute between 1 and 1000000),
    per_user_day integer not null check (per_user_day between 1 and 1000000),
    global_minute integer not null check (global_minute between 1 and 1000000),
    global_day integer not null check (global_day between 1 and 1000000)
);
create table if not exists feel_admission.counters (
    operation text not null references feel_admission.policies(operation),
    -- All-zero UUID is reserved for the operation's global counter.
    subject uuid not null,
    minute_start timestamptz not null,
    day_start timestamptz not null,
    minute_count bigint not null default 0 check (minute_count >= 0),
    day_count bigint not null default 0 check (day_count >= 0),
    primary key (operation, subject)
);
alter table feel_admission.policies enable row level security;
alter table feel_admission.counters enable row level security;
revoke all on feel_admission.policies, feel_admission.counters from public, anon, authenticated;
-- Policies are operator-managed; the service RPC only reads them.
grant select on feel_admission.policies to service_role;
grant select, insert, update on feel_admission.counters to service_role;
drop policy if exists admission_policy_service_read on feel_admission.policies;
create policy admission_policy_service_read on feel_admission.policies for select to service_role using (true);
drop policy if exists admission_counter_service_read on feel_admission.counters;
create policy admission_counter_service_read on feel_admission.counters for select to service_role using (true);
drop policy if exists admission_counter_service_insert on feel_admission.counters;
create policy admission_counter_service_insert on feel_admission.counters for insert to service_role with check (true);
drop policy if exists admission_counter_service_update on feel_admission.counters;
create policy admission_counter_service_update on feel_admission.counters for update to service_role using (true) with check (true);

create or replace function public.feel_reserve_admission(p_user_id uuid, p_operation text)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
set lock_timeout = '2s'
as $function$
declare
    policy feel_admission.policies%rowtype;
    global_row feel_admission.counters%rowtype;
    user_row feel_admission.counters%rowtype;
    global_id constant uuid := '00000000-0000-0000-0000-000000000000';
    operation_lock integer;
    current_time_utc timestamptz;
    minute_start_utc timestamptz;
    day_start_utc timestamptz;
    global_minute_used bigint;
    global_day_used bigint;
    user_minute_used bigint;
    user_day_used bigint;
    wait_seconds integer := 0;
begin
    -- ACL plus explicit role check: user JWTs cannot call this RPC directly.
    if current_user <> 'service_role' then
        raise exception 'Admission role required' using errcode = '42501';
    end if;
    operation_lock := case p_operation
        when 'voice_session' then 1 when 'context_last_seen' then 2
        when 'context_room_structure' then 3 when 'context_room_anchors' then 4 else null end;
    if p_user_id is null or p_user_id = global_id or operation_lock is null then
        raise exception 'Invalid admission request' using errcode = '22023';
    end if;
    -- One transaction lock per operation serializes reservation across every
    -- server instance. Distinct fixed operation IDs cannot collide with each other.
    perform pg_catalog.pg_advisory_xact_lock(1447380300, operation_lock);
    select * into policy from feel_admission.policies where operation = p_operation;
    if not found or not policy.enabled then
        return pg_catalog.jsonb_build_object('allowed', false, 'reason', 'not_enabled', 'retry_after_seconds', 0);
    end if;
    current_time_utc := pg_catalog.clock_timestamp();
    minute_start_utc := pg_catalog.date_trunc('minute', current_time_utc, 'UTC');
    day_start_utc := pg_catalog.date_trunc('day', current_time_utc, 'UTC');
    insert into feel_admission.counters(operation, subject, minute_start, day_start)
        values (p_operation, global_id, minute_start_utc, day_start_utc),
               (p_operation, p_user_id, minute_start_utc, day_start_utc)
        on conflict (operation, subject) do nothing;
    select * into strict global_row from feel_admission.counters
        where operation = p_operation and subject = global_id for update;
    select * into strict user_row from feel_admission.counters
        where operation = p_operation and subject = p_user_id for update;
    global_minute_used := case when global_row.minute_start = minute_start_utc then global_row.minute_count else 0 end;
    global_day_used := case when global_row.day_start = day_start_utc then global_row.day_count else 0 end;
    user_minute_used := case when user_row.minute_start = minute_start_utc then user_row.minute_count else 0 end;
    user_day_used := case when user_row.day_start = day_start_utc then user_row.day_count else 0 end;
    if global_minute_used >= policy.global_minute or user_minute_used >= policy.per_user_minute then
        wait_seconds := greatest(1, ceil(extract(epoch from minute_start_utc + interval '1 minute' - current_time_utc))::integer);
    end if;
    if global_day_used >= policy.global_day or user_day_used >= policy.per_user_day then
        wait_seconds := greatest(wait_seconds, 1, ceil(extract(epoch from day_start_utc + interval '1 day' - current_time_utc))::integer);
    end if;
    if wait_seconds > 0 then
        return pg_catalog.jsonb_build_object('allowed', false, 'reason', 'quota_exceeded', 'retry_after_seconds', wait_seconds);
    end if;
    update feel_admission.counters set minute_start = minute_start_utc, day_start = day_start_utc,
        minute_count = global_minute_used + 1, day_count = global_day_used + 1
        where operation = p_operation and subject = global_id;
    update feel_admission.counters set minute_start = minute_start_utc, day_start = day_start_utc,
        minute_count = user_minute_used + 1, day_count = user_day_used + 1
        where operation = p_operation and subject = p_user_id;
    return pg_catalog.jsonb_build_object('allowed', true, 'reason', 'allowed', 'retry_after_seconds', 0);
end;
$function$;
revoke all on function public.feel_reserve_admission(uuid, text) from public, anon, authenticated;
grant execute on function public.feel_reserve_admission(uuid, text) to service_role;
-- No enabled policy is seeded. Missing or disabled policy denies all admissions.
commit;
