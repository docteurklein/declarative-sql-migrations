create procedure webhook(
    slot text,
    _url text,
    polls int default null,
    sleep int default 1,
    tables_like text[] default null
)
language plpgsql
set search_path to pgdiff, public
set parallel_setup_cost = 0
set parallel_tuple_cost = 0
as $$
declare
    response http_response;
    i int = 1;
begin
    perform http_set_curlopt('curlopt_timeout', '30');
    perform http_set_curlopt('curlopt_connecttimeout', '10');

    while coalesce(i <= polls, true) loop
        raise debug 'polling %...', i;
        perform (with change as (
            select jsonb_array_elements(data::jsonb->'change') as change
            from pg_logical_slot_get_changes(
                slot,
                null,
                null,
                'pretty-print', '1',
                'add-msg-prefixes',
                'wal2json',
                'include-default', '1',
                'format-version', '1'
            )
        )
        select _log(http((
            'POST',
            _url,
            array[http_header('accept','application/json')],
            'application/json',
            change
        )::http_request))
        from change
        where case when tables_like is not null
            then format('%s.%s', change->>'schema', change->>'table') like any(tables_like)
            else true
            end
        );
        i := i + 1;
        perform pg_sleep(sleep);
    end loop;
end;
$$;
