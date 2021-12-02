create or replace function pgdiff.http(request public.http_request)
returns public.http_response
language plpgsql parallel safe
set search_path to pgdiff, public
set parallel_setup_cost = 0
set parallel_tuple_cost = 0
as $$
begin
  perform http_set_curlopt('curlopt_timeout', '30');
  perform http_set_curlopt('curlopt_connecttimeout', '10');

  return public.http(request);
end;
$$;

create procedure webhook(
    slot text,
    _url text
)
language plpgsql
set search_path to pgdiff, public
set parallel_setup_cost = 0
set parallel_tuple_cost = 0
as $$
declare
    response public.http_response;
    d record;
begin
    while true loop
        raise debug 'polling...';
        perform _log(data), _log(pgdiff.http((
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
        perform pg_sleep(1);
    end loop;
end;
$$;

