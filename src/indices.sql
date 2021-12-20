create or replace function pgdiff.alterations(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pg_catalog
as $$
with index_to_create as (
    with missing as (
        select dc.relname, di.indrelid::regclass, di.indexrelid
        from pg_index di
        join pg_class dc
            on di.indexrelid = dc.oid
            and dc.relnamespace = desired::regnamespace::oid
        left join pg_class tc
            on tc.relname = dc.relname
            and tc.relnamespace = to_regnamespace(target)::oid
        where tc.oid is null
        and not di.indisprimary
        and not di.indisunique
    )
    select 6, 'create index',
    pg_get_indexdef(indexrelid),
    jsonb_build_object(
        'schema_name', target,
        'index_name', relname,
        'table_name', indrelid
    )
    from missing
),
index_to_drop as (
    with extra as (
        select tc.relname, dt.relname as table_name
        from pg_index ti
        join pg_class tc
            on ti.indexrelid = tc.oid
            and tc.relnamespace = to_regnamespace(target)::oid
        left join pg_class dc
            on dc.relname = tc.relname
            and dc.relnamespace = desired::regnamespace::oid
        left join pg_class dt on dt.oid = ti.indrelid
        where dc.oid is null
        and not ti.indisprimary
        and not ti.indisunique
    )
    select 6, 'drop index', format(
        'drop index %I.%I',
        target,
        relname
    ), jsonb_build_object(
        'schema_name', target,
        'index_name', relname,
        'table_name', table_name
    )
    from extra
)
select a::pgdiff.alteration from (
    table index_to_create
    union table index_to_drop
    order by 1, 2
) a
$$;
