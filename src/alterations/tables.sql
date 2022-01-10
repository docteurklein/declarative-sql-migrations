create or replace function pgdiff.altered_tables(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with table_to_create as (
    select 1, 'create table',
    format('create table %I.%I ()', target, tablename),
    jsonb_build_object(
        'schema_name', target,
        'table_name', tablename
    )
    from pg_tables dt
    where schemaname = desired
    and not exists (
        select from pg_tables
        where schemaname = target
        and tablename = dt.tablename
    )
),
table_to_drop as (
    select 7, 'drop table',
    format('drop table %I.%I%s', target, tablename,
        case cascade when true then ' cascade' else '' end
    ),
    jsonb_build_object(
        'schema_name', target,
        'table_name', tablename,
        'cascade', cascade
    )
    from pg_tables dt
    where schemaname = target
    and not exists (
        select from pg_tables
        where schemaname = desired
        and tablename = dt.tablename
    )
)
select a::alteration from (
    table table_to_create
    union table table_to_drop
    order by 1, 2
) a
$$;
