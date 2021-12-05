set local search_path to pgdiff;

create or replace function query(sql text)
returns setof record
language plpgsql strict volatile
set search_path to pgdiff
as $$
begin
    return query execute sql;
end;
$$;
