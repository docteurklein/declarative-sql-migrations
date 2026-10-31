\set ON_ERROR_STOP on

create extension if not exists postgres_fdw;

create server if not exists :target foreign data wrapper postgres_fdw options (dbname :'target');

create user mapping if not exists for current_user server :target;

drop schema if exists shadow cascade;
create schema shadow;

import foreign schema pg_catalog except (
    pg_attribute, -- anyarray pseudotype error
    pg_attrdef, -- node_tree error
    pg_replication_slots,
    pg_statistic,
    pg_statistic_ext_data,
    pg_stats,
    pg_stats_ext_exprs
)
from server :target
into shadow;

create foreign table shadow.pg_attribute (
    attrelid oid not null,
    attname name,
    atttypid oid,
    attlen smallint,
    attnum smallint not null,
    atttypmod integer,
    attndims smallint,
    attbyval boolean,
    attalign "char",
    attstorage "char",
    attcompression "char",
    attnotnull boolean,
    atthasdef boolean,
    atthasmissing boolean,
    attidentity "char",
    attgenerated "char",
    attisdropped boolean,
    attislocal boolean,
    attinhcount smallint,
    attcollation oid,
    attstattarget smallint,
    attacl aclitem[],
    attoptions text[],
    attfdwoptions text[]
)
server :target
options (schema_name 'pg_catalog', table_name 'pg_attribute');

create foreign table shadow.pg_attrdef (
    oid oid not null,
    adrelid oid not null,
    adnum smallint not null,
    expr text collate "C" not null
)
server :target
options (schema_name 'fdw_friendly_catalog', table_name 'pg_attrdef');

drop view if exists shadow.alter_ddl cascade;
create or replace view shadow.alter_ddl (ddl) as
with schema_target (oid, nspname) as (
    select oid, nspname
    from shadow.pg_namespace
    where nspname not in ('pg_catalog', 'pg_toast', 'pg_temp', 'fdw_friendly_catalog', 'shadow', 'information_schema')
),
schema_desired (oid, nspname) as (
    select oid, nspname
    from pg_catalog.pg_namespace
    where nspname not in ('pg_catalog', 'pg_toast', 'pg_temp', 'fdw_friendly_catalog', 'shadow', 'information_schema')
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
attr_target (schema, rel, attname, type, not_null, expr, attgenerated, attidentity) as (
    select nspname, relname, attname,
        format_type(atttypid, atttypmod),
        attnotnull,
        expr,
        attgenerated,
        attidentity
    end
    from shadow.pg_attribute a
    left join shadow.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join shadow.pg_class c on (c.oid = a.attrelid)
    join schema_target s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
    and not attisdropped
),
attr_desired (schema, rel, attname, type, not_null, expr, attgenerated, attidentity) as (
    select nspname, relname, attname,
        format_type(atttypid, atttypmod),
        attnotnull,
        pg_get_expr(adbin, adrelid, true),
        attgenerated,
        attidentity
    from pg_catalog.pg_attribute a
    left join pg_catalog.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join pg_catalog.pg_class c on (c.oid = a.attrelid)
    join schema_desired s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
    and not attisdropped
),
attr_to_add as (
    select *
    from attr_desired d
    where not exists (select from attr_target t where (d.schema, d.rel, d.attname) = (t.schema, t.rel, t.attname))
),
attr_diff as (
    select d, t
    from attr_desired d
    full outer join attr_target t using (schema, rel, attname)
    where d is distinct from t
    and not exists (select from schema_to_drop to_d where to_d.schema = d.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (d.schema, d.rel))
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
        when attidentity <> ''
            then format(' generated %s as identity',
                case attidentity when 'a' then 'always' when 'd' then 'by default' end
            )
        else ''
    end
)
from attr_to_add
union all
select format('alter table %I.%I drop column %I;', (t).schema, (t).rel, (t).attname)
from attr_diff
where (d).attname is null
union all
select format('alter table %I.%I alter column %I %s;', (d).schema, (d).rel, (d).attname, action)
from attr_diff,
lateral (values
    (format('type %I', (d).type),              (d).type <> (t).type),
    (format('set default %s', (d).expr),       (d).expr <> (t).expr and (d).expr <> '' and (d).attgenerated = ''),
    ('drop default',                           (d).expr <> (t).expr and (d).expr = '' and (d).attgenerated = ''),
    (format('set expression as %s', (d).expr), (d).expr <> (t).expr and (d).expr <> '' and (d).attgenerated <> ''),
    ('drop expression',                        (d).expr <> (t).expr and (d).expr = '' and (d).attgenerated <> ''),
    (
        format('add generated %s as identity', case (d).attidentity when 'a' then 'always' when 'd' then 'by default' end),
        (d).attidentity <> (t).attidentity and (t).attidentity = ''
    ),
    (
        format('set generated %s', case (d).attidentity when 'a' then 'always' when 'd' then 'by default' end),
        (d).attidentity <> (t).attidentity and (d).attidentity  <> '' and (t).attidentity <> ''
    ),
    (
        'drop identity',
        (d).attidentity <> (t).attidentity and (d).attidentity = ''
    ),
    ('set not null',                           (d).not_null <> (t).not_null and (d).not_null),
    ('drop not null',                          (d).not_null <> (t).not_null and not (d).not_null)
) _ (action, applies)
where (d).attname is not null
and applies
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
