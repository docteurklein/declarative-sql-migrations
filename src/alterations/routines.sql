create or replace function pgdiff.altered_routines(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with routine_to_drop as (
    select 7, 'drop routine',
    format('drop routine if exists %I.%I (%s)%s', target, proname,
        pg_get_function_identity_arguments(oid),
        case cascade when true then ' cascade' else '' end
    ),
    jsonb_build_object(
        'schema_name', target,
        'routine_name', proname
    )
    from pg_proc tp
    where pronamespace = to_regnamespace(target)::oid
    and not exists (
        select from pg_proc dp
        where pronamespace = desired::regnamespace::oid
        and (
            tp.proname, tp.prosrc, tp.proisstrict,
            tp.proretset, tp.provolatile, tp.proparallel, tp.pronargs, tp.pronargdefaults
        ) = (
            dp.proname, replace(dp.prosrc, format('%I.', desired), format('%I.', target)), dp.proisstrict,
            dp.proretset, dp.provolatile, dp.proparallel, dp.pronargs, dp.pronargdefaults
        )
    )
),
routine_to_create as (
    select 8, 'create routine',
    replace(pg_get_functiondef(oid), format('%I.', desired), format('%I.', target)), -- bad
    jsonb_build_object(
        'schema_name', target,
        'routine_name', proname
    )
    from pg_proc dp
    where pronamespace = desired::regnamespace::oid
    and not exists (
        select from pg_proc tp
        where pronamespace = to_regnamespace(target)::oid
        and (
            tp.proname, tp.prosrc, tp.proisstrict,
            tp.proretset, tp.provolatile, tp.proparallel, tp.pronargs, tp.pronargdefaults
        ) = (
            dp.proname, replace(dp.prosrc, format('%I.', desired), format('%I.', target)), dp.proisstrict,
            dp.proretset, dp.provolatile, dp.proparallel, dp.pronargs, dp.pronargdefaults
        )
    )
)
select a::alteration from (
    table routine_to_drop
    union table routine_to_create
    order by 1, 2
) a
$$;
