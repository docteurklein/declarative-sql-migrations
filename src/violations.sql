drop type if exists pgdiff.status cascade;
create type pgdiff.status as enum ('valid', 'invalid check', 'null', 'unknown');

create or replace function pgdiff.is_valid(key text, value anyelement, type_ text, coid oid)
returns pgdiff.status
language plpgsql strict volatile
set search_path to pgdiff
as $$
begin
    execute format(
	'with _row(%I) as (select $1::%I) select from _row where %s',
	key,
	type_,
	trim(leading 'CHECK ' from pg_get_constraintdef(coid))
    ) using value;

    case when found then
	return 'valid'::status;
    else
	return 'invalid check'::status;
    end case;
end;
$$;

create or replace function pgdiff.violations(
    record jsonb,
    toid oid
) returns table (
    col text,
    name text,
    def text,
    status status
)
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
    select
	e.key,
	c.conname,
	pg_get_constraintdef(c.oid),
	coalesce(
	    -- case when a.attname is null then 'unknown'::status else null end,
	    -- case when a.attnotnull then
	    --     (case when value is null then 'null'::status else null end)
	    --     else null
	    -- end,
	    is_valid(e.key, e.value, format_type(t.oid, null), c.oid)
	)
    from jsonb_each_text(record) e
    left join pg_attribute a
        on a.attname = e.key
        and a.attrelid = toid
    left join pg_constraint c
        on a.attnum = any(c.conkey) 
	and c.conrelid = toid
	and c.contype in ('c') -- f, p, u
    left join pg_type t
        on a.atttypid = t.oid
$$;
