create procedure webhook(
    slot text,
    _url text,
    polls int default null,
    sleep int default 1
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
        perform _log(data), _log(http((
            'post',
            _url,
            array[http_header('accept','application/json')],
            'application/json',
            data::jsonb->'change'
        )::http_request))
        from pg_logical_slot_get_changes(
            slot,
            null,
            null,
            'pretty-print', '1',
            'add-msg-prefixes',
            'wal2json',
            'include-default', '1',
            'format-version', '1'
        );
        i := i + 1;
        perform pg_sleep(sleep);
    end loop;
end;
$$;
