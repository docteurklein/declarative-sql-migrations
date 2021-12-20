create or replace function pgdiff._exec(inout sql text)
returns text
language plpgsql strict volatile
set search_path to pgdiff
as $$
begin
    execute sql;
end;
$$;
