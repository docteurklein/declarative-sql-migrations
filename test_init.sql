\set ON_ERROR_STOP on

set plpgsql.extra_warnings to 'all';
set plpgsql.extra_errors to 'all';

create extension if not exists plpgsql_check cascade;

drop schema if exists pgdiff_test cascade;
create schema pgdiff_test;

set search_path to pgdiff_test, pgdiff, public;

create or replace function pgdiff._log(e anyelement, msg text default null) returns anyelement
language plpgsql strict as $$
begin
    raise notice '% %', e, msg;
    return e;
end;
$$;

create or replace function pgdiff_test.throws(
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

create or replace function pgdiff_test.timing(statement text) returns interval
language plpgsql as $$
declare start timestamp;
begin
    start := clock_timestamp();
    execute statement;
    return clock_timestamp() - start;
end;
$$;
