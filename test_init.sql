\set ON_ERROR_STOP on

\i diff.sql

set search_path to pgdiff;

create function throws(statement text) returns bool
language plpgsql as $$
begin
    execute statement;
    return false;
exception when others then
    return true;
end;
$$;
