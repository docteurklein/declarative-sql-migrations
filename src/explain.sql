create or replace function pgdiff.explain_analyze(sql text)
returns table(path text, value jsonb, type text, depth int)
language sql strict volatile
set search_path to pgdiff
as $$
with recursive plan as materialized (
    select jsonb_array_elements(plans::jsonb) plan
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
    ) %s', sql)) _ (plans json)
),
_tree (path, value, type, depth) as (
    select null, plan, 'object', 0
    from plan
    union all (
        with typed_values as materialized (
            select path, jsonb_typeof(value) as typeof, value, depth + 1 as depth
            from _tree
        )
        select concat(tv.path, '.', v.key), v.value, jsonb_typeof(v.value), depth
        from typed_values as tv,
        lateral jsonb_each(value) v
        where typeof = 'object'
            union all
        select concat(tv.path, '[', n - 1, ']'), v.value, jsonb_typeof(v.value), depth
        from typed_values as tv,
        lateral jsonb_array_elements(value) with ordinality as v (value, n)
        where typeof = 'array'
    )
)
select distinct path, value, type, depth
from _tree
where path is not null
order by path
$$;
