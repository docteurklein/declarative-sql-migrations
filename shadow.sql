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

create table shadow.excluded_schema (
    nspname text primary key
);
insert into shadow.excluded_schema values
    ('pg_catalog'), ('pg_toast'), ('pg_temp'), ('fdw_friendly_catalog'), ('shadow'), ('information_schema')
;

create or replace function shadow.schema_diff()
returns table (
    nspname text, drop bool
)
begin atomic
with shadow as (
    select nspname
    from shadow.pg_namespace n
    where not exists (select from shadow.excluded_schema e where e.nspname = n.nspname)
),
current as (
    select nspname
    from pg_catalog.pg_namespace n
    where not exists (select from shadow.excluded_schema e where e.nspname = n.nspname)
)
select *, current is null
from shadow
natural full outer join current
where current is distinct from shadow
;
end;

drop function if exists shadow.privilege_diff cascade;
create or replace function shadow.privilege_diff()
returns table (
    schema text, privilege text, type text, "on" text, "to" text, drop bool
)
begin atomic
with shadow as (
    select nspname, privilege_type, 'table', c.relname, r.rolname
    from shadow.pg_class c
    left join shadow.pg_attribute_fdw a on a.attrelid = c.oid
    join shadow.pg_namespace s on (s.oid = c.relnamespace)
    , aclexplode(coalesce(
        c.relacl,
        acldefault(case when c.relkind <> 'S' then 'r' end::"char", c.relowner)
    )) acl
    join shadow.pg_authid r on r.oid = acl.grantee
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and c.relkind in ('r', 'p', 'v', 'm', 'S')
),
current as (
    select nspname, privilege_type, 'table', c.relname, r.rolname
    from pg_catalog.pg_class c
    left join pg_catalog.pg_attribute a on a.attrelid = c.oid
    join pg_catalog.pg_namespace s on (s.oid = c.relnamespace)
    , aclexplode(coalesce(
        c.relacl,
        acldefault(case when c.relkind <> 'S' then 'r' end::"char", c.relowner)
    )) acl
    join pg_catalog.pg_authid r on r.oid = acl.grantee
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and c.relkind in ('r', 'p', 'v', 'm', 'S')
)
select *, current is null
from shadow
natural full outer join current
where current is distinct from shadow
;
end;

drop function if exists shadow.type_diff cascade;
create or replace function shadow.type_diff()
returns table (
    schema text, oid text, name text, def text, typtype text, typrelid oid, drop bool
)
begin atomic
with shadow as (
    select nspname, t.oid, typname, format_type, typtype, typrelid
    from shadow.pg_type_fdw t
    join shadow.pg_namespace s on (s.oid = t.typnamespace)
    left join shadow.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e')
    and (relkind = 'c' or relkind is null)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
current as (
    select nspname, t.oid, typname, format_type(t.oid, typtypmod), typtype, typrelid
    from pg_catalog.pg_type t
    join pg_catalog.pg_namespace s on (s.oid = typnamespace)
    left join pg_catalog.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e') -- see https://www.postgresql.org/docs/current/catalog-pg-type.html#id-1.10.4.64.4
    and (relkind = 'c' or relkind is null)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
)
select *, current is null
from shadow
natural full outer join current
where current is distinct from shadow
;
end;

drop function if exists shadow.alter_ddl;
create or replace function shadow.alter_ddl(if_exists text default ' if exists', cascade text default ' cascade')
returns setof text
language sql
volatile parallel safe
begin atomic
with recursive
type_shadow (schema, name, def, typtype, typrelid) as (
    select nspname, typname, format_type, typtype, typrelid
    from shadow.pg_type_fdw t
    join shadow.pg_namespace s on (s.oid = t.typnamespace)
    left join shadow.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e')
    and (relkind = 'c' or relkind is null)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
type_current (schema, oid, name, def, typtype, typrelid) as (
    select nspname, t.oid, typname, format_type(t.oid, typtypmod), typtype, typrelid
    from pg_catalog.pg_type t
    join pg_namespace s on (s.oid = typnamespace)
    left join pg_catalog.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e') -- see https://www.postgresql.org/docs/current/catalog-pg-type.html#id-1.10.4.64.4
    and (relkind = 'c' or relkind is null)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
type_to_add as (
    select *
    from type_current d
    where not exists (select from type_shadow t where (t.schema, t.name) = (d.schema, d.name))
),
type_to_drop as (
    select *
    from type_shadow t
    where not exists (select from type_current d where (t.schema, t.name) = (d.schema, d.name))
    and not exists (select from shadow.schema_diff() to_d where to_d.nspname = t.schema and to_d.drop)
),
domain_shadow (schema, name, def) as (
    select nspname, t.typname, format('%s%s;', format_type(bt.oid, t.typtypmod), case when c.oid is not null
        then format (' constraint %I %s',
            c.conname,
            pg_get_constraintdef
        )
        else ''
    end)
    from shadow.pg_type_fdw t
    join shadow.pg_namespace s on (s.oid = t.typnamespace)
    left join shadow.pg_constraint_fdw c
        on t.oid = c.contypid
    join shadow.pg_type_fdw bt on t.typbasetype = bt.oid
    where t.typtype in ('d')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
domain_current (schema, name, def) as (
    select nspname, t.typname, format('%s%s;', format_type(bt.oid, t.typtypmod), case when c.oid is not null
        then format (' constraint %I %s',
            c.conname,
            pg_get_constraintdef(c.oid)
        )
        else ''
    end)
    from pg_catalog.pg_type t
    join pg_namespace s on (s.oid = t.typnamespace)
    left join pg_catalog.pg_constraint c
        on t.oid = c.contypid
    join pg_catalog.pg_type bt on t.typbasetype = bt.oid
    where t.typtype in ('d')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
domain_diff as (
    select d, t
    from domain_current d
    natural full outer join domain_shadow t
    where d is distinct from t
    -- and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
),
table_shadow (schema, rel) as (
    select nspname, relname
    from shadow.pg_class c
    join shadow.pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
table_current (schema, rel) as (
    select nspname, relname
    from pg_catalog.pg_class c
    join pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
table_to_add (schema, rel) as (
    select d.schema, d.rel
    from table_current d
    where not exists (select from table_shadow t where (d.schema, d.rel) = (t.schema, t.rel))
),
table_to_drop (schema, rel) as (
    select schema, rel
    from table_shadow t
    where not exists (select from table_current d where (d.schema, d.rel) = (t.schema, t.rel))
    -- and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
),
attr_shadow (schema, rel, attname, type, not_null, expr, attgenerated, attidentity) as (
    select s.nspname, relname, attname,
        format_type,
        attnotnull,
        expr,
        attgenerated,
        attidentity
    end
    from shadow.pg_attribute_fdw a
    left join shadow.pg_attrdef_fdw ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join shadow.pg_class c on (c.oid = a.attrelid)
    join shadow.pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
    and not attisdropped
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
attr_current (schema, rel, attname, type, not_null, expr, attgenerated, attidentity) as (
    select s.nspname, relname, attname,
        format_type(atttypid, atttypmod) collate "C",
        attnotnull,
        pg_get_expr(adbin, adrelid, true),
        attgenerated,
        attidentity
    from pg_catalog.pg_attribute a
    left join pg_catalog.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join pg_catalog.pg_class c on (c.oid = a.attrelid)
    join pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
    and not attisdropped
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
attr_to_add as (
    select *
    from attr_current d
    where not exists (select from attr_shadow t where (d.schema, d.rel, d.attname) = (t.schema, t.rel, t.attname))
),
attr_to_alter as (
    select d, t
    from attr_current d
    full outer join attr_shadow t using (schema, rel, attname)
    where d is distinct from t
    -- and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
),
rls_shadow as (
    select p.*
    from shadow.pg_policies p
    join shadow.pg_namespace s on (s.nspname = p.schemaname)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
rls_current as (
    select p.*
    from pg_catalog.pg_policies p
    join pg_namespace s on (s.nspname = p.schemaname)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
rls_diff as (
    select d, t
    from rls_current d
    full outer join rls_shadow t using (schemaname, tablename, policyname)
    where d is distinct from t
    -- and not exists (select from schema_to_drop to_d where to_d.schema = t.schemaname)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schemaname, t.tablename))
),
index_shadow (schema, rel, index, def) as (
    select nspname, rel.relname, ic.relname, pg_get_indexdef(ic.oid)
    from shadow.pg_index i
    join shadow.pg_class rel on (rel.oid = i.indrelid)
    join shadow.pg_class ic on (ic.oid = i.indexrelid)
    join shadow.pg_namespace s on (s.oid = ic.relnamespace)
    where not indisprimary -- covered by constraint
    and not indisunique
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
index_current (schema, rel, index, def) as (
    select nspname, rel.relname, ic.relname, pg_get_indexdef(ic.oid)
    from pg_catalog.pg_index i
    join pg_class rel on (rel.oid = i.indrelid)
    join pg_class ic on (ic.oid = i.indexrelid)
    join pg_namespace s on (s.oid = ic.relnamespace)
    where not indisprimary -- covered by constraint
    and not indisunique
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
index_to_add as (
    select *
    from index_current d
    where not exists (select from index_shadow t where (d.schema, d.rel) = (t.schema, t.rel))
),
index_to_drop as (
    select *
    from index_shadow t
    where not exists (select from index_current d where (d.schema, d.rel) = (t.schema, t.rel))
    -- and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
),
constraint_shadow (schema, rel, name, def, type, is_deferrable, is_deferred) as (
    select nspname, relname, c.conname, pg_get_constraintdef, contype, condeferrable, condeferred
    from shadow.pg_constraint_fdw c
    join shadow.pg_class rel on (rel.oid = c.conrelid)
    join shadow.pg_namespace s on (s.oid = c.connamespace)
    where contype not in ('n')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
constraint_current (schema, rel, name, def, type, is_deferrable, is_deferred) as (
    select nspname, relname, c.conname, pg_get_constraintdef(c.oid) collate "C", contype, condeferrable, condeferred
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class rel on (rel.oid = c.conrelid)
    join pg_namespace s on (s.oid = c.connamespace)
    where contype not in ('n')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
constraint_diff as (
    select d, t
    from constraint_current d
    full outer join constraint_shadow t using (schema, rel, name)
    where d is distinct from t
    -- and not exists (select from shadow.schema_diff(excluded_schemas) to_d where to_d.nspname = t.schema)
    and not exists (select from table_to_drop to_d where (to_d.schema, to_d.rel) = (t.schema, t.rel))
    order by case (d).type when 'p' then 1 when 'u' then 2 end nulls last
),
view_shadow (schema, rel, def) as (
    select schemaname, viewname, definition
    from shadow.pg_views v
    join shadow.pg_namespace s on (s.nspname = v.schemaname)
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
),
view_current (schema, oid, rel, def) as (
    select s.nspname, c.oid, c.relname, pg_get_viewdef(c.oid)
    from pg_catalog.pg_class c
    join pg_namespace s on (s.oid = c.relnamespace)
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and c.relkind in ('v')
),
view_to_add as (
    select d.*
    from view_current d
    full outer join view_shadow t using (schema, rel)
    where t.rel is null or d.def <> t.def
    -- where not exists (select from view_shadow t where (d.schema, d.rel) = (t.schema, t.rel))
),
view_dep (f, t) as (
    select o.oid, ref.oid
    from pg_depend dep
    join pg_rewrite r on (r.oid = dep.objid)
    join pg_class o on (o.oid = r.ev_class)
    join pg_class ref on (ref.oid = dep.refobjid)
    join pg_namespace s on (s.oid = o.relnamespace)
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
    from view_shadow t
    where not exists (select from view_current d where (d.schema, d.rel) = (t.schema, t.rel))
    -- and not exists (select from schema_to_drop to_d where to_d.schema = t.schema)
),
routine_shadow (schema, name, def, args) as (
    select nspname, proname, pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
    from shadow.pg_proc p
    join shadow.pg_namespace s on (s.oid = p.pronamespace)
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and prokind <> 'a'
),
routine_current (schema, name, def, args) as (
    select nspname, proname, pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
    from pg_catalog.pg_proc p
    join pg_namespace s on (s.oid = p.pronamespace)
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and prokind <> 'a'
),
routine_to_add as (
    select d.*
    from routine_current d
    where not exists (select from routine_shadow t where (d.schema, d.name) = (t.schema, t.name))
),
routine_to_drop as (
    select *
    from routine_shadow t
    where not exists (select from routine_current d where (d.schema, d.name) = (t.schema, t.name))
    and not exists (select from shadow.schema_diff() to_d where to_d.nspname = t.schema and to_d.drop)
)
select format('drop schema%s %I%s;', if_exists, nspname, cascade)
from shadow.schema_diff()
where drop

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
select format('create schema %I;', nspname)
from shadow.schema_diff()
where not drop

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
        format('set expression as (%s)', (d).expr),
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
select format('alter table %I.%I drop constraint%s %I%s;', (t).schema, (t).rel, if_exists, (t).name, cascade)
from constraint_diff r
where (t).name is not null

union all
select format('alter table %I.%I add constraint %I %s;', (d).schema, (d).rel, (d).name, (d).def)
from constraint_diff
where (d).name is not null

union all
select format('alter table %I.%I alter constraint %I %s%s;', (d).schema, (d).rel, (d).name,
    case when (d).is_deferrable then 'deferrable' else 'not deferrable' end,
    case when (d).is_deferred then ' initially deferred' else ' initially immediate' end
)
from constraint_diff
where (d).is_deferrable <> (t).is_deferrable
or (d).is_deferred <> (t).is_deferred

union all
select format('%s;', def)
from routine_to_add

union all (
    select format('create or replace view %I.%I as %s', schema, rel, def)
    from view_sort
)

union all
select format('drop policy%s %I on %I.%I%s;', if_exists, (t).policyname, (t).schemaname, (t).tablename, cascade)
from rls_diff
where (t).policyname is not null

union all
select format('create policy %I on %I.%I as %s for %s to %s%s%s;',
    (d).policyname, (d).schemaname, (d).tablename,
    (d).permissive,
    (d).cmd,
    concat_ws(', ', variadic (d).roles),
    case when (d).qual is not null then format(' using (%s)', (d).qual) end,
    case when (d).with_check is not null then format(' with check (%s)', (d).with_check) end
)
from rls_diff r
where (d).policyname is not null

union all
select format('revoke %s on %s %I.%I from %s;', privilege, type, schema, "on", "to")
from shadow.privilege_diff()
where drop

union all
select format('grant %s on %s %I.%I to %s;', privilege, type, schema, "on", "to")
from shadow.privilege_diff()
where not drop
;
end;
