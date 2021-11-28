
create procedure migrate(
    desired text,
    target text,
    dry_run bool default true,
    keep_data bool default false,
    cascade bool default false,
    lock_timeout text default '50ms',
    max_attempts int default 30,
    cap_ms bigint default 60000,
    base_ms bigint default 10,
    sqlstates text[] default '{}'::text[]
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
                base_ms => base_ms,
                sqlstates => sqlstates
            );
            else raise notice '%', ddl;
        end if;
    end loop;
end;
$$;
