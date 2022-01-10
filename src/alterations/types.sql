create or replace function pgdiff.altered_types(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with type_to_drop as (
    select 1, 'drop type',
    format('drop type %I.%I%s', target, typname,
        case cascade when true then ' cascade' else '' end
    ),
    jsonb_build_object(
        'schema_name', target,
        'type_name', typname
    )
    from pg_type tt
    left join pg_class tc on tt.typrelid = tc.oid
    where typnamespace = to_regnamespace(target)::oid
    and (tc.relkind = 'c' or tc.relkind is null)
    and typtype in ('c', 'e') -- see https://www.postgresql.org/docs/current/catalog-pg-type.html#id-1.10.4.64.4
    and not exists (
        select from pg_type dt
        where typnamespace = desired::regnamespace::oid
        and dt.typname = tt.typname
        and dt.typtype = tt.typtype
        and array(
            select quote_literal(enumlabel) from pg_enum where enumtypid = dt.oid
            order by enumsortorder
        ) = array(
            select quote_literal(enumlabel) from pg_enum where enumtypid = tt.oid
            order by enumsortorder
        )
        and array(
            select row(attname, replace(format_type(atttypid, a.atttypmod), format('%I.', desired), format('%I.', target)))
            from pg_attribute a
            join pg_class c on dt.typrelid = c.oid
            and a.attrelid = c.oid
        ) = array(
            select row(attname, replace(format_type(atttypid, a.atttypmod), format('%I.', desired), format('%I.', target)))
            from pg_attribute a
            join pg_class c on tt.typrelid = c.oid
            and a.attrelid = c.oid
        )
    )
),
type_to_create as (
    select 2, 'create type',
    format('create type %I.%I as %s', target, typname,
        case typtype
            when 'e' then format(E'enum (\n  %s\n)', array_to_string(array(
                select quote_literal(enumlabel) from pg_enum where enumtypid = dt.oid
                order by enumsortorder
            ), E',\n  '))
            when 'c' then format(E'(\n  %s\n)', array_to_string(array(
                select format('%I %s', attname::text,
                replace(format_type(atttypid, a.atttypmod), format('%I.', desired), format('%I.', target))) -- bad
                from pg_attribute a
                join pg_class c on dt.typrelid = c.oid
                join pg_type t on a.atttypid = t.oid
                and a.attrelid = c.oid
            ), E',\n  '))
            else ''
        end
    ),
    jsonb_build_object(
        'schema_name', target,
        'type_name', typname
    )
    from pg_type dt
    left join pg_class dc on dt.typrelid = dc.oid
    where typnamespace = desired::regnamespace::oid
    and typtype in ('c', 'e') -- see https://www.postgresql.org/docs/current/catalog-pg-type.html#id-1.10.4.64.4
    and (dc.relkind = 'c' or dc.relkind is null)
    and not exists (
        select from pg_type tt
        where typnamespace = to_regnamespace(target)::oid
        and dt.typname = tt.typname
        and dt.typtype = tt.typtype
        and array(
            select quote_literal(enumlabel) from pg_enum where enumtypid = dt.oid
            order by enumsortorder
        ) = array(
            select quote_literal(enumlabel) from pg_enum where enumtypid = tt.oid
            order by enumsortorder
        )
        and array(
            select row(attname, replace(format_type(atttypid, a.atttypmod), format('%I.', desired), format('%I.', target)))
            from pg_attribute a
            join pg_class c on dt.typrelid = c.oid
            and a.attrelid = c.oid
        ) = array(
            select row(attname, replace(format_type(atttypid, a.atttypmod), format('%I.', desired), format('%I.', target)))
            from pg_attribute a
            join pg_class c on tt.typrelid = c.oid
            and a.attrelid = c.oid
        )
    )
)
select a::alteration from (
    table type_to_drop
    union table type_to_create
    order by 1, 2
) a
$$;
