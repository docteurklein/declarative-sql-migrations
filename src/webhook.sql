create or replace procedure pgdiff.webhook(
    slot text, -- an exising locgical replication slot with wal2json
    _url text, -- url to push to
    polls int default null, -- number of times to poll before returning
    sleep int default 1, -- sleep interval
    tables_like text[] default null -- only changes matching `schema.table` (f.e: `public.app_%`)
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
        raise debug 'polling %: %...', slot, i;
        perform _log(data, 'body'), _log(public.http((
            'POST',
            _url,
            array[http_header('accept','application/json')],
            'application/json',
            data
        )::http_request), 'response')
        from pg_logical_slot_get_changes(
            slot,
            null,
            null,
            'pretty-print', '0',
            'include-default', '1',
            'format-version', '1'
        )
        cross join jsonb_array_elements(data::jsonb->'change') as change
        where case when tables_like is not null
            then format('%s.%s', change->>'schema', change->>'table') like any(tables_like)
            else true
            end
        ;
        i := i + 1;
        perform pg_sleep(sleep);
    end loop;
end;
$$;

create or replace function pgdiff.http(request public.http_request)
returns public.http_response
language plpgsql parallel safe -- make it parallelizable
set search_path to pgdiff, public
set parallel_setup_cost = 0
set parallel_tuple_cost = 0
as $$
begin
  return public.http(request);
end;
$$;
