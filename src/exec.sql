create procedure exec(
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
    completed bool = false;
    begin
        perform set_config('lock_timeout', lock_timeout, false);
        for i in 1..max_attempts - 1 loop
            begin
                raise notice 'executing "%"', statement;
                execute statement;
                completed = true;
                exit;
            exception when others then
                if (select cardinality(sqlstates) = 0 or array[sqlstate] && sqlstates) then
                    delay_ms := round(random() * least(cap_ms, base_ms * 2 ^ i));
                    -- raise warning 'attempt %/% for statement "%" failed, retrying in %ms', i, max_attempts, statement, delay_ms;
                    raise warning e'%/%: "%" throws exception "%: %"', i, max_attempts, statement, sqlstate, sqlerrm;

                    perform pg_sleep(delay_ms::numeric / 1000);
                else
                    raise;
                end if;
            end;
        end loop;
        if not completed then
            raise exception 'attempt %/% for statement "%" failed', max_attempts, max_attempts, statement;
        end if;
    end;
$$;
