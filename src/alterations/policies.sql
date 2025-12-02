create or replace function pgdiff.altered_policies(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with policy_to_drop as (
    select 'drop policy',
    format('drop policy %I on %I.%I %s;', p.polname, target, c.relname,
        case cascade when true then ' cascade' else '' end
    ),
    jsonb_build_object(
        'schema_name', target,
        'policy_name', p.polname
    )
    from pg_policy p
    join pg_class c on (c.oid = p.polrelid)
    where c.relnamespace = to_regnamespace(target)
    and not exists (
        select from pg_policy op
        join pg_class c on (c.oid = op.polrelid)
        where c.relnamespace = desired::regnamespace
        and p.polname = op.polname
    )
),
policy_to_create as (
    select 'create policy',
    format('create policy %I on %I.%I as %s for %s to %s %s %s;',
        p.polname, target, c.relname,
        case when polpermissive then 'permissive' else 'restrictive' end,
        case polcmd when 'r' then 'select' when 'a' then 'insert' when 'w' then 'update' when 'd' then 'delete' when '*' then 'all' end,
        (select string_agg(rolname, ', ') from pg_authid where oid = any(polroles)),
        case when polqual is not null then
            format('using (%s)', replace(pg_get_expr(p.polqual, t.oid), format('%I.', desired), format('%I.', target))) -- bad
        end,
        case when polwithcheck is not null then
            format('with check (%s)', replace(pg_get_expr(p.polwithcheck, t.oid), format('%I.', desired), format('%I.', target))) -- bad
        end
    ),
    jsonb_build_object(
        'schema_name', target,
        'policy_name', p.polname
    )
    from pg_policy p
    join pg_class c on (c.oid = p.polrelid)
    join pg_class t on (t.relnamespace = to_regnamespace(target) and t.relname = c.relname)
    where c.relnamespace = desired::regnamespace
    and not exists (
        select from pg_policy op
        join pg_class c on (c.oid = op.polrelid)
        where c.relnamespace = to_regnamespace(target)
        and p.polname = op.polname
    )
)
select a::alteration from (
    table policy_to_drop
    union all table policy_to_create
) a
$$;
