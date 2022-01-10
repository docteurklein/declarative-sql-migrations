create or replace function pgdiff.explain_analyze(sql text)
returns table(path text, value jsonb, depth int)
language sql strict volatile
set search_path to pgdiff
as $$
with recursive plans as (
    select plan::jsonb
    from query(format('explain (
        analyze,
        verbose,
        costs,
        settings,
        buffers,
        wal,
        timing,
        summary,
        format json
    ) %s',
 sql)) _ (plan json)
),
plan as (
    select jsonb_array_elements(plan) plan
    from plans
),
flat (path, value, depth) as (
    select key, value, 0
    from plan,
    jsonb_each(plan)
    where jsonb_typeof(plan) = 'object'
    union all
    select concat(f.path, '.', j.key), j.value, depth + 1
    from flat f,
    jsonb_each(f.value) j
    where jsonb_typeof(f.value) = 'object'
)
select path, value, depth
from flat
$$;

