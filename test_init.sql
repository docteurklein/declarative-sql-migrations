\set ON_ERROR_STOP on

set plpgsql.extra_warnings to 'all';
set plpgsql.extra_errors to 'all';

create extension if not exists plpgsql_check cascade;

set search_path to pgdiff, pgdiff_test, public;

create or replace function _log(e anyelement, msg text default null) returns anyelement
language plpgsql strict as $$
begin
    raise notice '% %', e, msg;
    return e;
end;
$$;

create or replace function throws(
    statement text,
    message_like text default null,
    sqlstates text[] default '{}'::text[]
) returns bool
language plpgsql as $$
begin
    execute statement;
    return false;
exception when others then
    raise debug e'"%" throws exception "%: %"', statement, sqlstate, sqlerrm;
    return
        (
            (cardinality(sqlstates) = 0 or array[sqlstate] && sqlstates)
            and
            (message_like is null or sqlerrm ilike message_like)
        )
    ;
end;
$$;

create or replace function timing(statement text) returns interval
language plpgsql as $$
declare start timestamp;
begin
    start := clock_timestamp();
    execute statement;
    return clock_timestamp() - start;
end;
$$;
