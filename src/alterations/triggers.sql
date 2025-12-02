create or replace function pgdiff.altered_triggers(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with trigger_to_drop as (
    select 'drop trigger',
    format('drop trigger %I on %I.%I %s;', t.tgname, target, c.relname,
        case cascade when true then ' cascade' else '' end
    ),
    jsonb_build_object(
        'schema_name', target,
        'trigger_name', t.tgname
    )
    from pg_trigger t
    join pg_class c on (c.oid = t.tgrelid)
    where c.relnamespace = to_regnamespace(target)::oid
    and not t.tgisinternal
    and not exists (
        select from pg_trigger ot
        join pg_class c on (c.oid = ot.tgrelid)
        where c.relnamespace = desired::regnamespace::oid
        and t.tgname = ot.tgname
        and not t.tgisinternal
    )
),
trigger_to_create as (
    select 'create trigger',
    replace(pg_get_triggerdef(t.oid), format('%I.', desired), format('%I.', target)) || ';', -- bad
    jsonb_build_object(
        'schema_name', target,
        'trigger_name', t.tgname
    )
    from pg_trigger t
    join pg_class c on (c.oid = t.tgrelid)
    where c.relnamespace = desired::regnamespace::oid
    and not t.tgisinternal
    and not exists (
        select from pg_trigger ot
        join pg_class c on (c.oid = ot.tgrelid)
        where c.relnamespace = to_regnamespace(target)::oid
        and t.tgname = ot.tgname
    )
)
select a::alteration from (
    table trigger_to_drop
    union all table trigger_to_create
) a
$$;
