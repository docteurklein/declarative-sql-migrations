create or replace function pgdiff.alterations(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with schema_to_create as (
    select 0, 'create schema'::ddl_type,
    format('create schema %I', target),
    jsonb_build_object(
        'schema_name', target
    )
    from pg_namespace
    where not exists (
        select from pg_namespace where nspname = target
    )
)
select a::alteration from (
    table schema_to_create
    union select * from altered_columns(desired, target, cascade => cascade)
    union select * from altered_constraints(desired, target, cascade => cascade)
    union select * from altered_types(desired, target, cascade => cascade)
    union select * from altered_domains(desired, target, cascade => cascade)
    union select * from altered_routines(desired, target, cascade => cascade)
    union select * from altered_tables(desired, target, cascade => cascade)
    union select * from altered_indices(desired, target, cascade => cascade)
    order by 1, 2
) a
$$;
