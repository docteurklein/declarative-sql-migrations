create or replace function pgdiff.altered_constraints(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pg_catalog
as $$
with constraint_to_create as (
    with missing as (
        select dcl.relname, dc.conname, dc.oid, dc.contype
        from pg_constraint dc
        join pg_class dcl on dcl.oid = dc.conrelid
        left join pg_constraint tc
            on tc.conname = dc.conname
            and tc.connamespace = to_regnamespace(target)::oid
        where tc.oid is null
        and dc.contype in ('f', 'p', 'c', 'u')
        and dc.connamespace = desired::regnamespace
    )
    select
        case contype when 'p' then 4 else 5 end, -- primary key first
        'alter table add constraint',
        format('alter table %I.%I add constraint %s %s',
            target,
            relname,
            conname,
            pg_get_constraintdef(oid)
        ),
        jsonb_build_object(
            'schema_name', target,
            'constraint_name', conname,
            'table_name', relname
        )
    from missing
),
constraint_to_alter as (
    with different as (
        select dcl.relname, dc.conname,
            dc.condeferrable as _deferrable,
            dc.condeferred as deferred
        from pg_constraint dc
        join pg_class dcl on dcl.oid = dc.conrelid
        left join pg_constraint tc
            on tc.conname = dc.conname
            and tc.connamespace = to_regnamespace(target)::oid
        where (
            tc.condeferred != dc.condeferred
            or tc.condeferrable != dc.condeferrable
        )
        and dc.contype in ('f') -- only fkeys are supported in postgres
        and dc.connamespace = desired::regnamespace
    )
    select 5, 'alter table alter constraint', format(
        'alter table %I.%I alter constraint %s %s %s',
        target,
        relname,
        conname,
        case _deferrable::bool
            when true then 'deferrable'
            else 'not deferrable'
        end,
        case when deferred::bool
            then 'initially deferred'
            else 'initially immediate'
        end
    ), jsonb_build_object(
        'schema_name', target,
        'constraint_name', conname,
        'table_name', relname,
        'deferrable', _deferrable,
        'deferred', deferred
    ) from different
),
constraint_to_drop as (
    with extra as (
        select dcl.relname, dc.conname
        from pg_constraint dc
        join pg_class dcl on dcl.oid = dc.conrelid
        left join pg_constraint tc
            on tc.conname = dc.conname
            and tc.connamespace = desired::regnamespace::oid
        where tc.oid is null
        and dc.contype in ('f', 'p', 'c', 'u')
        and dc.connamespace = to_regnamespace(target)
    )
    select 4, 'alter table drop constraint',
    format('alter table %I.%I drop constraint %s',
        target,
        relname,
        conname
    ), jsonb_build_object(
        'schema_name', target,
        'constraint_name', conname,
        'table_name', relname
    ) from extra
)
select a::pgdiff.alteration from (
    table constraint_to_create
    union table constraint_to_alter
    union table constraint_to_drop
    order by 1, 2
) a
$$;
