\set ON_ERROR_STOP on

set search_path to pgdiff;

\i diff.sql
\i src/throws.sql
\i src/time.sql

create procedure assert_equals(expected text, actual text, context text default '')
language plpgsql as $$
begin
    assert expected = actual;
exception when assert_failure then
    raise notice 'expected %, got % (%)', expected, actual, context;
    raise;
end;
$$;

create function id(inout record)
language plpgsql as $$
begin
    raise notice '%', $1;
end;
$$;
