create or replace procedure exec(
    statement text,
    lock_timeout text default '50ms',
    max_attempts int default 30,
    cap_ms bigint default 60000,
    base_ms bigint default 10,
    sqlstates text[] default '{}'::text[]
)
language plpgsql as $$
declare
    delay_ms bigint = null;
    begin
        perform set_config('lock_timeout', lock_timeout, true);
        for i in 1..max_attempts loop
            begin
                raise notice 'executing "%"', statement;
                execute statement;
                exit;
            exception when others then
                if (select cardinality(sqlstates) = 0 or array[sqlstate] && sqlstates) then
                    delay_ms := round(random() * least(cap_ms, base_ms * 2 ^ i));

                    if i = max_attempts then
                        raise;
                    end if;

                    raise warning e'attempt %/% for statement "%" throws exception "%: %"\nsleeping %ms', i, max_attempts, statement, sqlstate, sqlerrm, delay_ms;

                    perform pg_sleep(delay_ms::numeric / 1000);
                else
                    raise;
                end if;
            end;
        end loop;
    end;
$$;
