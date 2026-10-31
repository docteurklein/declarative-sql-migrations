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
    select nspname
    from schema_desired d
    where not exists (select from schema_target t where t.nspname = d.nspname)
),
schema_to_drop (schema) as (
    select nspname
    from schema_target t
    where not exists (select from schema_desired d where d.nspname = t.nspname)
),
table_target (schema, rel) as (
    select nspname, relname
    from shadow.pg_class c
    join schema_target s on (s.oid = c.relnamespace)
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
    where not exists (select from table_target t where (d.schema, d.rel) = (t.schema, t.rel))
),
table_to_drop (schema, rel) as (
    select schema, rel
    from table_target t
    where not exists (select from table_desired d where (d.schema, d.rel) = (t.schema, t.rel))
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
),
attr_target (schema, rel, attname, type, not_null, expr, attgenerated) as (
    select nspname, relname, attname,
        format_type(atttypid, atttypmod),
        attnotnull,
        expr,
        attgenerated
    end
    from shadow.pg_attribute a
    left join shadow.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join shadow.pg_class c on (c.oid = a.attrelid)
    join schema_target s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
),
attr_desired (schema, rel, attname, type, not_null, expr, attgenerated) as (
    select nspname, relname, attname,
        format_type(atttypid, atttypmod),
        attnotnull,
        pg_get_expr(adbin, adrelid, true),
        attgenerated
    from pg_catalog.pg_attribute a
    left join pg_catalog.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join pg_catalog.pg_class c on (c.oid = a.attrelid)
    join schema_desired n on (n.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
),
attr_to_add as (
    select *
    from attr_desired d
    where not exists (select from attr_target t where (d.schema, d.rel, d.attname) = (t.schema, t.rel, t.attname))
),
attr_to_drop as (
    select *
    from attr_target t
    -- full outer join attr_desired d using ()
    where not exists (select from attr_desired d where (d.schema, d.rel, d.attname) = (t.schema, t.rel, t.attname))
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
),
attr_to_alter as (
    select *
    from attr_desired d
    where not exists (select from attr_target t where (d.schema, d.rel, d.attname) = (t.schema, t.rel, t.attname))
),
index_target (schema, rel, index, def) as (
    select schemaname, tablename, indexname, indexdef
    from shadow.pg_indexes i
    join schema_target s on (s.nspname = i.schemaname)
),
index_desired (schema, rel, index, def) as (
    select schemaname, tablename, indexname, indexdef
    from pg_catalog.pg_indexes i
    join schema_desired s on (s.nspname = i.schemaname)
),
index_to_add as (
    select *
    from index_desired d
    where not exists (select from index_target t where (d.schema, d.rel) = (t.schema, t.rel))
),
index_to_drop as (
    select *
    from index_target t
    where not exists (select from index_desired d where (d.schema, d.rel) = (t.schema, t.rel))
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
),
view_target (schema, rel, def) as (
    select schemaname, viewname, definition
    from shadow.pg_views v
    join schema_target s on (s.nspname = v.schemaname)
),
view_desired (schema, rel, def) as (
    select schemaname, viewname, definition
    from pg_catalog.pg_views v
    join schema_desired s on (s.nspname = v.schemaname)
),
view_to_add as (
    select *
    from view_desired d
    where not exists (select from view_target t where (d.schema, d.rel) = (t.schema, t.rel))
),
view_to_drop as (
    select *
    from view_target t
    where not exists (select from view_desired d where (d.schema, d.rel) = (t.schema, t.rel))
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
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
select format('alter table %I.%I add column %I %s%s%s;',
    schema,
    rel,
    attname,
    type,
    case not_null
        when true then ' not null'
        else ''
    end,
    case
        when expr <> '' and attgenerated = ''
            then format(' default %s', expr)
        when expr <> '' and attgenerated <> ''
            then format(' generated always as (%s) %s',
                expr,
                case attgenerated when 's' then 'stored' when 'v' then 'virtual' end
            )
        else ''
    end
)
from attr_to_add
union all
select format('alter table %I.%I drop column %I;', schema, rel, attname)
from attr_to_drop
union all
select format('%s;', def)
from index_to_add
union all
select format('drop index if exists %I.%I;', schema, rel)
from index_to_drop
union all
select format('create or replace view %I.%I as %s', schema, rel, def)
from view_to_add
union all
select format('drop view if exists %I.%I cascade;', schema, rel)
from view_to_drop
;
