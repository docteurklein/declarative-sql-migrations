create or replace function pgdiff.query(sql text, params jsonb = '{}'::jsonb)
returns setof record
language plpgsql strict volatile
set search_path to pgdiff
as $$
begin
    return query execute sql using params;
end;
$$;
