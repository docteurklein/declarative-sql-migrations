drop type if exists pgdiff.status cascade;
create type pgdiff.status as enum ('valid', 'invalid', 'null');

create or replace function pgdiff.is_valid(schema text, tbl text, key text, record jsonb, coid oid)
returns bool
language plpgsql strict volatile
set search_path to pgdiff
as $$
declare
    result record;
begin
    execute format(
	'select exists(select from jsonb_populate_record(null::%I.%I, $1) where %s) e',
	schema,
	tbl,
	trim(leading 'CHECK ' from pg_get_constraintdef(coid))
    ) strict into result using record;

    return result.e;
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
	a.attname,
	c.conname,
	pg_get_constraintdef(c.oid),
	coalesce(
	    case when a.attnotnull then
	        (case when value is null then 'null'::status else null end)
	        else null
	    end,
	    case is_valid(
		-- string_agg(quote_ident(key), ', ') from jsonb_object_keys(record),
		'desired',
		'test1',
		e.key,
		record,
		c.oid
	    ) when true then 'valid'::status else 'invalid'::status end
	)
    from pg_attribute a
    left join jsonb_each_text(record) e
        on a.attname = e.key
    left join pg_constraint c
        on a.attnum = any(c.conkey) 
	and c.conrelid = toid
	and c.contype in ('c') -- f, p, u
    left join pg_type t
        on a.atttypid = t.oid
    where a.attrelid = toid
    and a.attnum > 0
$$;
