\set ON_ERROR_STOP on

create extension if not exists postgres_fdw;

create server if not exists :"target" foreign data wrapper postgres_fdw options (:target);

create user mapping if not exists for current_user server :"target" options (:creds);

drop schema if exists shadow cascade;
create schema shadow;

import foreign schema pg_catalog except (
    pg_attribute, -- anyarray pseudotype error
    pg_type, -- format_type
    pg_attrdef, -- node_tree error
    pg_constraint,
    pg_replication_slots,
    pg_statistic,
    pg_statistic_ext_data,
    pg_stats,
    pg_stats_ext_exprs
)
from server :"target"
into shadow;

import foreign schema fdw_friendly_catalog -- alternatives to excluded above
from server :"target"
into shadow;

create function shadow.debug(a anyelement) returns anyelement
language plpgsql
volatile parallel safe
as $$
begin
    raise notice '% %', a, pg_typeof(a);
    return a;
end
$$;

drop function if exists shadow.alter_ddl;
create or replace function shadow.alter_ddl(exclude_schemas text[] default '{}', if_exists text default ' if exists', cascade text default ' cascade')
returns setof text
language sql
volatile parallel safe
begin atomic
with recursive schema_target (oid, nspname) as (
    select oid, nspname
    from shadow.pg_namespace
    where not nspname = any(array['pg_catalog', 'pg_toast', 'pg_temp', 'fdw_friendly_catalog', 'shadow', 'information_schema'] || exclude_schemas)
),
schema_desired (oid, nspname) as (
    select oid, nspname
    from pg_catalog.pg_namespace
    where not nspname = any(array['pg_catalog', 'pg_toast', 'pg_temp', 'fdw_friendly_catalog', 'shadow', 'information_schema'] || exclude_schemas)
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
type_target (schema, name, def, typtype, typrelid) as (
    select nspname, typname, formatted_type, typtype, typrelid
    from shadow.pg_type_fdw t
    join schema_target s on (s.oid = t.typnamespace)
    left join shadow.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e')
    and (relkind = 'c' or relkind is null)
),
type_desired (schema, oid, name, def, typtype, typrelid) as (
    select nspname, t.oid, typname, format_type(t.oid, typtypmod), typtype, typrelid
    from pg_catalog.pg_type t
    join schema_desired s on (s.oid = typnamespace)
    left join pg_catalog.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e') -- see https://www.postgresql.org/docs/current/catalog-pg-type.html#id-1.10.4.64.4
    and (relkind = 'c' or relkind is null)
),
type_to_add as (
    select *
    from type_desired d
    where not exists (select from type_target t where (t.schema, t.name) = (d.schema, d.name))
),
type_to_drop as (
    select *
    from type_target t
    where not exists (select from type_desired d where (t.schema, t.name) = (d.schema, d.name))
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
),
domain_target (schema, name, def) as (
    select nspname, t.typname, format('%s%s;', format_type(bt.oid, t.typtypmod), case when c.oid is not null
        then format (' constraint %I %s',
            c.conname,
            pg_get_constraintdef
        )
        else ''
    end)
    from shadow.pg_type_fdw t
    join schema_target s on (s.oid = t.typnamespace)
    left join shadow.pg_constraint_fdw c
        on t.oid = c.contypid
    join shadow.pg_type_fdw bt on t.typbasetype = bt.oid
    where t.typtype in ('d')
),
domain_desired (schema, name, def) as (
    select nspname, t.typname, format('%s%s;', format_type(bt.oid, t.typtypmod), case when c.oid is not null
        then format (' constraint %I %s',
            c.conname,
            pg_get_constraintdef(c.oid)
        )
        else ''
    end)
    from pg_catalog.pg_type t
    join schema_desired s on (s.oid = t.typnamespace)
    left join pg_catalog.pg_constraint c
        on t.oid = c.contypid
    join pg_catalog.pg_type bt on t.typbasetype = bt.oid
    where t.typtype in ('d')
),
domain_diff as (
    select d, t
    from domain_desired d
    natural full outer join domain_target t
    where d is distinct from t
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
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
    join schema_desired s on (s.oid = c.relnamespace)
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
    select s.nspname, relname, attname,
        formatted_type,
        attnotnull,
        expr,
        attgenerated,
        attidentity
    end
    from shadow.pg_attribute_fdw a
    left join shadow.pg_attrdef_fdw ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join shadow.pg_class c on (c.oid = a.attrelid)
    join schema_target s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
    and not attisdropped
),
attr_desired (schema, rel, attname, type, not_null, expr, attgenerated, attidentity) as (
    select s.nspname, relname, attname,
        format_type(atttypid, atttypmod) collate "C",
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
attr_to_alter as (
    select d, t
    from attr_desired d
    full outer join attr_target t using (schema, rel, attname)
    where d is distinct from t
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
),
index_target (schema, rel, index, def) as (
    select nspname, rel.relname, ic.relname, pg_get_indexdef(ic.oid)
    from shadow.pg_index i
    join shadow.pg_class rel on (rel.oid = i.indrelid)
    join shadow.pg_class ic on (ic.oid = i.indexrelid)
    join schema_target s on (s.oid = ic.relnamespace)
    where not indisprimary -- covered by constraint
    and not indisunique
),
index_desired (schema, rel, index, def) as (
    select nspname, rel.relname, ic.relname, pg_get_indexdef(ic.oid)
    from pg_catalog.pg_index i
    join pg_class rel on (rel.oid = i.indrelid)
    join pg_class ic on (ic.oid = i.indexrelid)
    join schema_desired s on (s.oid = ic.relnamespace)
    where not indisprimary -- covered by constraint
    and not indisunique
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
constraint_target (schema, rel, name, def, type, is_deferrable, is_deferred) as (
    select nspname, relname, c.conname, pg_get_constraintdef, contype, condeferrable, condeferred
    from shadow.pg_constraint_fdw c
    join shadow.pg_class rel on (rel.oid = c.conrelid)
    join schema_target s on (s.oid = c.connamespace)
    where contype not in ('c', 'n')
),
constraint_desired (schema, rel, name, def, type, is_deferrable, is_deferred) as (
    select nspname, relname, c.conname, pg_get_constraintdef(c.oid) collate "C", contype, condeferrable, condeferred
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class rel on (rel.oid = c.conrelid)
    join schema_desired s on (s.oid = c.connamespace)
    where contype not in ('c', 'n')
),
constraint_diff as (
    select d, t
    from constraint_desired d
    full outer join constraint_target t using (schema, rel, name)
    where d is distinct from t
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
    order by case (d).type when 'p' then 1 when 'u' then 2 end nulls last
),
view_target (schema, rel, def) as (
    select schemaname, viewname, definition
    from shadow.pg_views v
    join schema_target s on (s.nspname = v.schemaname)
),
view_desired (schema, oid, rel, def) as (
    select s.nspname, c.oid, c.relname, pg_get_viewdef(c.oid)
    from pg_catalog.pg_class c
    join schema_desired s on (s.oid = c.relnamespace)
    and c.relkind in ('v')
),
view_to_add as (
    select d.*
    from view_desired d
    full outer join view_target t using (schema, rel)
    where t.rel is null or d.def <> t.def
    -- where not exists (select from view_target t where (d.schema, d.rel) = (t.schema, t.rel))
),
view_dep (f, t) as (
    select o.oid, ref.oid
    from pg_depend dep
    join pg_rewrite r on (r.oid = dep.objid)
    join pg_class o on (o.oid = r.ev_class)
    join pg_class ref on (ref.oid = dep.refobjid)
    join schema_desired s on (s.oid = o.relnamespace)
    where r.ev_class <> refobjid
    and dep.classid = 'pg_rewrite'::regclass
    and dep.refclassid = 'pg_class'::regclass
    and o.relkind in ('v')
    and ref.relkind in ('v')
),
view_tree (f, t, priority) as (
    select *, 0
    from view_dep
    union all
    select d.*, priority + 1
    from view_tree f
    join view_dep d on (f.t = d.f)
),
view_dep_sort as (
    select f, t, sum(priority) priority
    from view_tree
    group by 1, 2
    order by 3 desc
),
view_sort as (
    select v.*, null priority
    from view_to_add v
    where not exists (select from view_dep where f = oid or t = oid)
    union 
    select v.*, priority
    from view_to_add v
    join view_dep_sort on (oid = t)
    union
    select v.*, priority
    from view_to_add v
    join view_dep_sort on (oid = f)
    order by priority desc nulls first
),
view_to_drop as (
    select *
    from view_target t
    where not exists (select from view_desired d where (d.schema, d.rel) = (t.schema, t.rel))
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
),
routine_target (schema, name, def, args) as (
    select nspname, proname, pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
    from shadow.pg_proc p
    join schema_target s on (s.oid = p.pronamespace)
),
routine_desired (schema, name, def, args) as (
    select nspname, proname, pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
    from pg_catalog.pg_proc p
    join schema_desired s on (s.oid = p.pronamespace)
),
routine_to_add as (
    select d.*
    from routine_desired d
    where not exists (select from routine_target t where (d.schema, d.name) = (t.schema, t.name))
),
routine_to_drop as (
    select *
    from routine_target t
    where not exists (select from routine_desired d where (d.schema, d.name) = (t.schema, t.name))
    and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
)
select format('drop schema%s %I%s;', if_exists, schema, cascade)
from schema_to_drop

union all
select format('drop view%s %I.%I%s;', if_exists, schema, rel, cascade)
from view_to_drop

union all
select format('drop routine%s %I.%I (%s)%s;', if_exists, schema, name, args, cascade)
from routine_to_drop

union all
select format('drop index%s %I.%I%s;', if_exists, schema, rel, cascade)
from index_to_drop

union all
select format('drop table%s %I.%I%s;', if_exists, schema, rel, cascade)
from table_to_drop

union all
select format('alter table %I.%I drop column%s %I;', (t).schema, (t).rel, if_exists, (t).attname)
from attr_to_alter
where (d).attname is null

union all
select format('drop domain%s %I.%I%s;', if_exists, (t).schema, (t).name, cascade)
from domain_diff
where (d).name is null and (t).name is not null

union all
select format('drop type%s %I.%I%s;', if_exists, schema, name, cascade)
from type_to_drop

union all
select format('create schema %I;', schema)
from schema_to_add

union all
select format('create type %I.%I as %s;', schema, name::text, case typtype
    when 'e' then format('enum (%s)', array_to_string(array(
        select quote_literal(enumlabel)
        from pg_enum
        where enumtypid = t.oid
        order by enumsortorder
    ), ',  '))
    when 'c' then format('(%s)', array_to_string(array(
        select format('%I %s', attname::text, format_type(atttypid, a.atttypmod))
        from pg_attribute a
        join pg_class c on typrelid = c.oid
        join pg_type t on a.atttypid = t.oid
        and a.attrelid = c.oid
    ), ',  '))
    else ''
end)
from type_to_add t

union all
select format('create domain %I.%I as %s', (d).schema, (d).name, (d).def)
from domain_diff
where (d).name is not null

union all
select format('create table %I.%I ();', schema, rel)
from table_to_add

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
select format('alter table %I.%I alter column %I %s;', (d).schema, (d).rel, (d).attname, action)
from attr_to_alter,
lateral (values
    (
        format('type %s', (d).type), -- @TODO using <expression>
        (d).type <> (t).type
    ),
    (
        format('set default %s', (d).expr),
        (d).expr <> (t).expr and (d).expr <> '' and (d).attgenerated = ''
    ),
    (
        'drop default',
        (d).expr <> (t).expr and (d).expr = '' and (d).attgenerated = ''
    ),
    (
        format('set expression as %s', (d).expr),
        (d).expr <> (t).expr and (d).expr <> '' and (d).attgenerated <> ''
    ),
    (
        'drop expression',
        (d).expr <> (t).expr and (d).expr = '' and (d).attgenerated <> ''
    ),
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
    (
        'set not null',
        (d).not_null <> (t).not_null and (d).not_null
    ),
    (
        'drop not null',
        (d).not_null <> (t).not_null and not (d).not_null
    )
) _ (action, applies)
where d is distinct from null
and applies

union all
select format('%s;', def)
from index_to_add

union all
select format('alter table %I.%I add constraint %I %s;', (d).schema, (d).rel, (d).name, (d).def)
from constraint_diff
where (t).name is null

union all
select format('alter table %I.%I drop constraint%s %I%s;', (t).schema, (t).rel, if_exists, (t).name, cascade)
from constraint_diff
where (d).name is null

union all
select format('alter table %I.%I alter constraint %I %s%s;', (d).schema, (d).rel, (d).name,
    case when (d).is_deferrable then 'deferrable' else 'not deferrable' end,
    case when (d).is_deferred then ' initially deferred' else ' initially immediate' end
)
from constraint_diff
where d <> t

union all (
    select format('create or replace view %I.%I as %s', schema, rel, def)
    from view_sort
)

union all
select def
from routine_to_add

;
end;
