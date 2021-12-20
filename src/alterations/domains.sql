create or replace function pgdiff.altered_domains(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pg_catalog
as $$
with domain_to_drop as (
    select 1, 'drop domain',
    format('drop domain %I.%I', target, dt.typname,
        case cascade when true then ' cascade' else '' end
    ),
    jsonb_build_object(
        'schema_name', target,
        'domain_name', dt.typname
    )
    from pg_type dt
    join pg_type bt on dt.typbasetype = bt.oid
    where dt.typnamespace = to_regnamespace(target)::oid
    and dt.typtype = 'd'
    and not exists (
        select from pg_type
        where typnamespace = desired::regnamespace::oid
        and typname = dt.typname
    )
),
domain_to_create as (
    select 3, 'create domain',
    format('create domain %I.%I as %I.%I%s', target, dt.typname, target, dbt.typname,
        case when dc.oid is not null
            then format (E'\nconstraint %I %s',
                dc.conname,
                -- pg_get_constraintdef(dc.oid)
                replace(pg_get_constraintdef(dc.oid), format('%I.', desired), format('%I.', target)) -- bad
            )
            else ''
        end
    ),
    jsonb_build_object(
        'schema_name', target,
        'domain_name', dt.typname
    )
    from pg_type dt
    left join pg_constraint dc
        on dt.oid = dc.contypid
    join pg_type dbt on dt.typbasetype = dbt.oid
    where dt.typnamespace = desired::regnamespace::oid
    and dt.typtype = 'd'
    and not exists (
        select from pg_type tt
        join pg_type tbt on tt.typbasetype = tbt.oid
        where tt.typnamespace = to_regnamespace(target)::oid
        and tt.typname = dt.typname
        and dbt.typname = tbt.typname
        and array(
            select replace(pg_get_constraintdef(oid), format('%I.', desired), format('%I.', target)) -- bad
            from pg_constraint
            where dt.oid = contypid
        ) = array(
            select replace(pg_get_constraintdef(oid), format('%I.', desired), format('%I.', target)) -- bad
            from pg_constraint
            where tt.oid = contypid
        )
    )
)
select a::pgdiff.alteration from (
    table domain_to_drop
    union table domain_to_create
    order by 1, 2
) a
$$;
