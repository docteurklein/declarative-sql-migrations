\set ON_ERROR_STOP on

set search_path to pgdiff, public;


\i diff.sql
\i src/throws.sql
\i src/time.sql

create extension plpgsql_check;

create procedure assert_equals(expected text, actual text, context text default '')
language plpgsql as $$
begin
    assert expected = actual;
exception when assert_failure then
    raise notice 'expected %, got % (%)', expected, actual, context;
    raise;
end;
$$;

create function id(e anyelement) returns anyelement
language plpgsql strict as $$
begin
    raise notice '%', e;
    return e;
end;
$$;
