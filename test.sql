\set ON_ERROR_STOP on

-- explain analyze
with schema_target (oid, nspname) as (
    select oid, nspname
    from shadow.pg_namespace
    where nspname not in ('pg_catalog', 'pg_toast', 'pg_temp', 'fdw_catalog', 'shadow')
),
schema_desired (oid, nspname) as (
    select oid, nspname
    from pg_catalog.pg_namespace
    where nspname not in ('pg_catalog', 'pg_toast', 'pg_temp', 'fdw_catalog', 'shadow')
),
schema_to_add (schema) as (
    select d.nspname
    from schema_desired d
    full outer join schema_target t using (nspname)
    where t is null
),
schema_to_drop (schema) as (
    select t.nspname
    from schema_desired d
    full outer join schema_target t using (nspname)
    where d is null
),
table_target (schema, rel) as (
    select nspname, relname
    from shadow.pg_class c
    join schema_target n on (n.oid = c.relnamespace)
    and relkind in ('r')
),
table_desired (schema, rel) as (
    select nspname, relname
    from pg_catalog.pg_class c
    join schema_desired n on (n.oid = c.relnamespace)
    and relkind in ('r')
),
table_to_add (schema, rel) as (
    select d.schema, d.rel
    from table_desired d
    full outer join table_target t using (schema, rel)
    where t is null
),
table_to_drop (schema, rel) as (
    select t.schema, t.rel
    from table_desired d
    full outer join table_target t using (schema, rel)
    where d is null
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
),
attr_target (schema, rel, attname, a, ad) as (
    select nspname, relname, attname, a, ad
    from shadow.pg_attribute a
    left join shadow.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join shadow.pg_class c on (c.oid = a.attrelid)
    join schema_target n on (n.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
),
attr_desired (schema, rel, attname, a, ad) as (
    select nspname, relname, attname, a, ad
    from pg_catalog.pg_attribute a
    left join pg_catalog.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join pg_catalog.pg_class c on (c.oid = a.attrelid)
    join schema_desired n on (n.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
),
attr_to_add as (
    select d.* from attr_desired d
    full outer join attr_target t using (schema, rel, attname)
    where t is null
),
attr_to_drop as (
    select t.* from attr_desired d
    full outer join attr_target t using (schema, rel, attname)
    where d is null
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
)
select format('create schema %I;', schema)
from schema_to_add
union all
select format('drop schema %I cascade;', schema)
from schema_to_drop
union all
select format('create table %I.%I ();', schema, rel)
from table_to_add
union all
select format('drop table %I.%I;', schema, rel)
from table_to_drop
union all
select format('alter table %I.%I add column %I %s%s%s%s;',
    schema,
    rel,
    attname,
    format_type((a).atttypid, (a).atttypmod),
    case (a).attnotnull
        when true then ' not null'
        else ''
    end,
    case when (a).atthasdef
        then format(' default %s', pg_get_expr((ad).adbin, (ad).adrelid, true))
        else ''
    end,
    case when (a).attgenerated <> ''
        then format(' generated always as (%s) %s',
            pg_get_expr((ad).adbin, (ad).adrelid, true),
            case (a).attgenerated when 's' then 'stored' when 'v' then 'virtual' end
        )
        else ''
    end
)
from attr_to_add
union all
select format('alter table %I.%I drop column %I;', schema, rel, attname)
from attr_to_drop
;
