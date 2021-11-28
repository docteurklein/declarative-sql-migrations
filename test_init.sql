\set ON_ERROR_STOP on

\i diff.sql

set search_path to pgdiff;

create function throws(
    statement text,
    sqlstates text[] default '{}'::text[]
) returns bool
language plpgsql as $$
begin
    execute statement;
    return false;
exception when others then
    raise debug e'"%" throws exception "%: %"', statement, sqlstate, sqlerrm;
    return array[sqlstate] && sqlstates;
end;
$$;
