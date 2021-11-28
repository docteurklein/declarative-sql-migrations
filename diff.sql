begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

set search_path to pgdiff;

create type ddl_type as enum (
    'create schema',
    'create table',
    'alter table add column',
    'alter table add constraint',
    'alter table alter constraint',
    'alter table drop constraint',
    'alter column set default',
    'alter column drop default',
    'alter column drop not null',
    'alter column set not null',
    'alter column type',
    'create index',
    'drop index',
    'drop table',
    'drop column'
);

create type alteration as (
    "order" int, -- smaller number means higher priority
    type ddl_type,
    details jsonb
);

\i src/format_ddl.sql
\i src/alterations.sql


create procedure exec(
    ddl text,
    lock_timeout text default '50ms',
    max_attempts int default 30,
    cap_ms bigint default 60000,
    base_ms bigint default 10
)
language plpgsql as $$
declare
    delay_ms bigint = null;
    ddl_completed bool = false;
    begin
        perform set_config('lock_timeout', lock_timeout, false);
        for i in 1..max_attempts - 1 loop
            begin
                raise notice '%', ddl;
                execute ddl;
                ddl_completed = true;
                exit;
            exception when lock_not_available then
                delay_ms := round(random() * least(cap_ms, base_ms * 2 ^ i));
                raise warning 'attempt %/% for ddl "%" failed, retrying in %ms', i, max_attempts, ddl, delay_ms;

                perform pg_sleep(delay_ms::numeric / 1000);
            end;
        end loop;
        if not ddl_completed then
            raise exception 'attempt %/% for ddl "%" failed', max_attempts, max_attempts, ddl;
        end if;
    end;
$$;

create procedure migrate(
    desired text,
    target text,
    dry_run bool default true,
    keep_data bool default false,
    cascade bool default false,
    lock_timeout text default '50ms',
    max_attempts int default 30,
    cap_ms bigint default 60000,
    base_ms bigint default 10
)
language plpgsql as $$
declare
    ddl text;
begin
    for ddl in
        select ddl(a, cascade) from alterations(desired, target) a
        where case when keep_data is true
            then type not in ('drop table', 'drop column')
            else true
            end
    loop
        if dry_run is false
            then call exec(
                ddl,
                lock_timeout => lock_timeout,
                max_attempts => max_attempts,
                cap_ms => cap_ms,
                base_ms => base_ms
            );
            else raise notice '%', ddl;
        end if;
    end loop;
end;
$$;

commit;
