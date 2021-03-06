create or replace procedure pgdiff.migrate(
    desired text,
    target text,
    dry_run bool default true,
    keep_data bool default false,
    lock_timeout text default '50ms',
    max_attempts int default 30,
    cap_ms bigint default 60000,
    base_ms bigint default 10,
    sqlstates text[] default '{}'::text[]
)
language plpgsql
set search_path to pgdiff
as $$
declare
    alteration alteration;
begin
    set local check_function_bodies to false; -- bad, dependency problem
    for alteration in
        select * from alterations(desired, target, cascade => true)
        where case when keep_data is true
            then type not in ('drop table', 'drop column')
            else true
            end
    loop
        if dry_run is false
            then call exec(
                alteration.ddl,
                lock_timeout => lock_timeout,
                max_attempts => max_attempts,
                cap_ms => cap_ms,
                base_ms => base_ms,
                sqlstates => sqlstates
            );
            else raise notice '%', alteration.ddl;
        end if;
    end loop;
end;
$$;
