\set ON_ERROR_STOP on

drop schema if exists shadow cascade;
create schema shadow;

drop schema if exists shadow_catalog cascade;
create schema shadow_catalog;

create extension if not exists postgres_fdw schema public;
create server if not exists :"target" foreign data wrapper postgres_fdw options (:target);
create user mapping if not exists for current_user server :"target" options (:creds);

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
into shadow_catalog;

import foreign schema fdw_friendly_catalog -- alternatives to excluded above
from server :"target"
into shadow_catalog;

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
    ('pg_catalog'), ('pg_toast'), ('pg_temp'), ('fdw_friendly_catalog'), ('shadow'), ('shadow_catalog'), ('information_schema')
;

create view shadow.extension_objects as
select classid, objid
from pg_catalog.pg_depend
where refclassid = 'pg_catalog.pg_extension'::regclass
and deptype = 'e';

drop view if exists shadow.schema_diff cascade;
create view shadow.schema_diff (
    nspname, drop
)
as
with shadow as (
    select nspname
    from shadow_catalog.pg_namespace n
    where not exists (select from shadow.excluded_schema e where e.nspname = n.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_namespace'::regclass and e.objid = n.oid)
),
current as (
    select nspname
    from pg_catalog.pg_namespace n
    where not exists (select from shadow.excluded_schema e where e.nspname = n.nspname)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_namespace'::regclass and e.objid = n.oid)
)
select *, current is null
from shadow
natural full outer join current
where current is distinct from shadow
;

drop view if exists shadow.type_diff cascade;
create view shadow.type_diff (
    schema, oid, name, def, typtype, typrelid, drop
)
as
with shadow as (
    select nspname, typname, format_type, typtype, typrelid
    from shadow_catalog.pg_type_fdw t
    join shadow_catalog.pg_namespace s on (s.oid = t.typnamespace)
    left join shadow_catalog.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e')
    and (relkind = 'c' or relkind is null)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_type'::regclass and e.objid = t.oid)
),
current as (
    select nspname, t.oid, typname, format_type(t.oid, typtypmod), typtype, typrelid
    from pg_catalog.pg_type t
    join pg_catalog.pg_namespace s on (s.oid = typnamespace)
    left join pg_catalog.pg_class c on typrelid = c.oid
    where typtype in ('c', 'e') -- see https://www.postgresql.org/docs/current/catalog-pg-type.html#id-1.10.4.64.4
    and (relkind = 'c' or relkind is null)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_type'::regclass and e.objid = t.oid)
)
select coalesce(current.nspname, shadow.nspname),
       current.oid::text,
       coalesce(current.typname, shadow.typname),
       coalesce(current.format_type, shadow.format_type),
       coalesce(current.typtype, shadow.typtype),
       coalesce(current.typrelid, shadow.typrelid),
       current is null
from shadow
full join current using (nspname, typname)
where (current is null or shadow is null)
and not exists (
    select from shadow.schema_diff to_d
    where to_d.drop and to_d.nspname = coalesce(shadow.nspname, current.nspname)
)
;

-- One diff view per component, following shadow.schema_diff:
-- `shadow` is the target catalog, `current` is the desired one, and `drop` means "only in target".

drop view if exists shadow.domain_diff cascade;
create view shadow.domain_diff (
    schema, name, def, drop
)
as
with shadow (nspname, typname, def) as (
    select nspname, t.typname, format('%s%s;', format_type(bt.oid, t.typtypmod), case when c.oid is not null
        then format (' constraint %I %s',
            c.conname,
            pg_get_constraintdef
        )
        else ''
    end)
    from shadow_catalog.pg_type_fdw t
    join shadow_catalog.pg_namespace s on (s.oid = t.typnamespace)
    left join shadow_catalog.pg_constraint_fdw c
        on t.oid = c.contypid
    join shadow_catalog.pg_type_fdw bt on t.typbasetype = bt.oid
    where t.typtype in ('d')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_type'::regclass and e.objid = t.oid)
),
current (nspname, typname, def) as (
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
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_type'::regclass and e.objid = t.oid)
)
select *, current is null
from shadow
natural full outer join current
where current is distinct from shadow
;

drop view if exists shadow.table_diff cascade;
create view shadow.table_diff (
    schema, rel, drop
)
as
with shadow (nspname, relname) as (
    select nspname, relname
    from shadow_catalog.pg_class c
    join shadow_catalog.pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = c.oid)
),
current (nspname, relname) as (
    select nspname, relname
    from pg_catalog.pg_class c
    join pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = c.oid)
)
select *, current is null
from shadow
natural full outer join current
where current is distinct from shadow
;

drop view if exists shadow.column_diff cascade;
create view shadow.column_diff (
    schema, rel, attname,
    current_type, current_not_null, current_expr, current_attgenerated, current_attidentity,
    shadow_type, shadow_not_null, shadow_expr, shadow_attgenerated, shadow_attidentity,
    drop, add
)
as
with shadow (nspname, relname, attname, type, not_null, expr, attgenerated, attidentity) as (
    select s.nspname, relname, attname,
        format_type,
        attnotnull,
        expr,
        attgenerated::text,
        attidentity::text
    from shadow_catalog.pg_attribute_fdw a
    left join shadow_catalog.pg_attrdef_fdw ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join shadow_catalog.pg_class c on (c.oid = a.attrelid)
    join shadow_catalog.pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
    and not attisdropped
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = a.attrelid)
),
current (nspname, relname, attname, type, not_null, expr, attgenerated, attidentity) as (
    select s.nspname, relname, attname,
        format_type(atttypid, atttypmod) collate "C",
        attnotnull,
        pg_get_expr(adbin, adrelid, true),
        attgenerated::text,
        attidentity::text
    from pg_catalog.pg_attribute a
    left join pg_catalog.pg_attrdef ad on (ad.adrelid = a.attrelid and ad.adnum = a.attnum)
    join pg_catalog.pg_class c on (c.oid = a.attrelid)
    join pg_namespace s on (s.oid = c.relnamespace)
    and relkind in ('r')
    and attnum >= 1
    and not attisdropped
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = a.attrelid)
),
diff as (
    select coalesce(shadow.nspname, current.nspname) as nspname,
           coalesce(shadow.relname, current.relname) as relname,
           coalesce(shadow.attname, current.attname) as attname,
           current.type as current_type,
           current.not_null as current_not_null,
           current.expr as current_expr,
           current.attgenerated as current_attgenerated,
           current.attidentity as current_attidentity,
           shadow.type as shadow_type,
           shadow.not_null as shadow_not_null,
           shadow.expr as shadow_expr,
           shadow.attgenerated as shadow_attgenerated,
           shadow.attidentity as shadow_attidentity,
           current is null as drop,
           shadow is null as add
    from shadow
    full join current using (nspname, relname, attname)
    where current is distinct from shadow
)
select nspname, relname, attname,
       current_type, current_not_null, current_expr, current_attgenerated, current_attidentity,
       shadow_type, shadow_not_null, shadow_expr, shadow_attgenerated, shadow_attidentity,
       drop, add
from diff d
where not exists (
    select from shadow.table_diff to_d
    where to_d.drop
    and (to_d.schema, to_d.rel) = (d.nspname, d.relname)
)
;

drop view if exists shadow.policy_diff cascade;
create view shadow.policy_diff (
    schemaname, tablename, policyname,
    current_permissive, current_roles, current_cmd, current_qual, current_with_check,
    shadow_permissive, shadow_roles, shadow_cmd, shadow_qual, shadow_with_check,
    drop, add
)
as
with shadow (schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check) as (
    select p.*
    from shadow_catalog.pg_policies p
    join shadow_catalog.pg_namespace s on (s.nspname = p.schemaname)
    join shadow_catalog.pg_class c on (c.relnamespace = s.oid and c.relname = p.tablename)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = c.oid)
),
current (schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check) as (
    select p.*
    from pg_catalog.pg_policies p
    join pg_namespace s on (s.nspname = p.schemaname)
    join pg_class c on (c.relnamespace = s.oid and c.relname = p.tablename)
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = c.oid)
),
diff as (
    select coalesce(shadow.schemaname, current.schemaname) as schemaname,
           coalesce(shadow.tablename, current.tablename) as tablename,
           coalesce(shadow.policyname, current.policyname) as policyname,
           current.permissive as current_permissive,
           current.roles as current_roles,
           current.cmd as current_cmd,
           current.qual as current_qual,
           current.with_check as current_with_check,
           shadow.permissive as shadow_permissive,
           shadow.roles as shadow_roles,
           shadow.cmd as shadow_cmd,
           shadow.qual as shadow_qual,
           shadow.with_check as shadow_with_check,
           current is null as drop,
           shadow is null as add
    from shadow
    full join current using (schemaname, tablename, policyname)
    where current is distinct from shadow
),
filtered as (
    select *
    from diff d
    where not exists (
        select from shadow.table_diff to_d
        where to_d.drop
        and (to_d.schema, to_d.rel) = (d.schemaname, d.tablename)
    )
)
select schemaname, tablename, policyname,
       current_permissive, current_roles, current_cmd, current_qual, current_with_check,
       shadow_permissive, shadow_roles, shadow_cmd, shadow_qual, shadow_with_check,
       true, false
from filtered
where not add

union all
select schemaname, tablename, policyname,
       current_permissive, current_roles, current_cmd, current_qual, current_with_check,
       shadow_permissive, shadow_roles, shadow_cmd, shadow_qual, shadow_with_check,
       false, add
from filtered
where not drop
;

drop view if exists shadow.index_diff cascade;
create view shadow.index_diff (
    schema, rel, index, def, drop
)
as
-- pg_get_indexdef() cannot be evaluated on foreign pg_class oids, so compare table presence only.
with shadow (nspname, relname, indexname, def) as (
    select nspname, rel.relname, ic.relname, pg_get_indexdef(ic.oid)
    from shadow_catalog.pg_index i
    join shadow_catalog.pg_class rel on (rel.oid = i.indrelid)
    join shadow_catalog.pg_class ic on (ic.oid = i.indexrelid)
    join shadow_catalog.pg_namespace s on (s.oid = ic.relnamespace)
    where not indisprimary -- covered by constraint
    and not indisunique -- covered by constraint
    and not indisexclusion -- covered by exclusion constraint
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = rel.oid)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = ic.oid)
),
current (nspname, relname, indexname, def) as (
    select nspname, rel.relname, ic.relname, pg_get_indexdef(ic.oid)
    from pg_catalog.pg_index i
    join pg_class rel on (rel.oid = i.indrelid)
    join pg_class ic on (ic.oid = i.indexrelid)
    join pg_namespace s on (s.oid = ic.relnamespace)
    where not indisprimary -- covered by constraint
    and not indisunique -- covered by constraint
    and not indisexclusion -- covered by exclusion constraint
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = rel.oid)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = ic.oid)
),
shadow_tables (nspname, relname) as (
    select distinct nspname, relname from shadow
),
current_tables (nspname, relname) as (
    select distinct nspname, relname from current
),
diff as (
    select nspname, relname, current_tables is null as drop
    from shadow_tables
    natural full outer join current_tables
    where current_tables is distinct from shadow_tables
    and not exists (
        select from shadow.table_diff to_d
        where to_d.drop
        and (to_d.schema, to_d.rel) = (nspname, relname)
    )
)
select d.nspname, d.relname, s.indexname, s.def, true
from diff d
join shadow s using (nspname, relname)
where d.drop

union all
select d.nspname, d.relname, c.indexname, c.def, false
from diff d
join current c using (nspname, relname)
where not d.drop
;

drop view if exists shadow.constraint_diff cascade;
create view shadow.constraint_diff (
    schema, rel, name,
    current_def, current_type, current_is_deferrable, current_is_deferred,
    shadow_def, shadow_type, shadow_is_deferrable, shadow_is_deferred,
    drop, add
)
as
with shadow (nspname, relname, conname, def, type, is_deferrable, is_deferred) as (
    select nspname, relname, c.conname, pg_get_constraintdef, contype::text, condeferrable, condeferred
    from shadow_catalog.pg_constraint_fdw c
    join shadow_catalog.pg_class rel on (rel.oid = c.conrelid)
    join shadow_catalog.pg_namespace s on (s.oid = c.connamespace)
    where contype not in ('n')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_constraint'::regclass and e.objid = c.oid)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = rel.oid)
),
current (nspname, relname, conname, def, type, is_deferrable, is_deferred) as (
    select nspname, relname, c.conname, pg_get_constraintdef(c.oid) collate "C", contype::text, condeferrable, condeferred
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class rel on (rel.oid = c.conrelid)
    join pg_namespace s on (s.oid = c.connamespace)
    where contype not in ('n')
    and not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_constraint'::regclass and e.objid = c.oid)
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = rel.oid)
),
diff as (
    select coalesce(shadow.nspname, current.nspname) as nspname,
           coalesce(shadow.relname, current.relname) as relname,
           coalesce(shadow.conname, current.conname) as conname,
           current.def as current_def,
           current.type as current_type,
           current.is_deferrable as current_is_deferrable,
           current.is_deferred as current_is_deferred,
           shadow.def as shadow_def,
           shadow.type as shadow_type,
           shadow.is_deferrable as shadow_is_deferrable,
           shadow.is_deferred as shadow_is_deferred,
           current is null as drop,
           shadow is null as add
    from shadow
    full join current using (nspname, relname, conname)
    where current is distinct from shadow
)
select nspname, relname, conname,
       current_def, current_type, current_is_deferrable, current_is_deferred,
       shadow_def, shadow_type, shadow_is_deferrable, shadow_is_deferred,
       drop, add
from diff d
where not exists (
    select from shadow.table_diff to_d
    where to_d.drop
    and (to_d.schema, to_d.rel) = (d.nspname, d.relname)
)
order by case current_type when 'p' then 1 when 'u' then 2 end nulls last
;

drop view if exists shadow.view_diff cascade;
create view shadow.view_diff (
    schema, oid, rel, def, drop, priority, drop_first
)
as
-- drop_first marks views that depend on a table with column changes. PostgreSQL
-- refuses to change such a column while a view's _RETURN rule uses it, so the
-- view must be dropped before the table is altered and recreated afterwards.
with recursive
view_shadow (nspname, relname, def) as (
    select schemaname, viewname, definition
    from shadow_catalog.pg_views v
    join shadow_catalog.pg_namespace s on (s.nspname = v.schemaname)
    join shadow_catalog.pg_class vc on (vc.relnamespace = s.oid and vc.relname = v.viewname and vc.relkind = 'v')
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = vc.oid)
),
view_current (nspname, oid, relname, def) as (
    select s.nspname, c.oid, c.relname, pg_get_viewdef(c.oid)
    from pg_catalog.pg_class c
    join pg_namespace s on (s.oid = c.relnamespace)
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and c.relkind in ('v')
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = c.oid)
),
-- every pg_class referenced by a view's _RETURN rule (tables and views)
view_ref (view_oid, ref_oid) as (
    select o.oid, dep.refobjid
    from pg_depend dep
    join pg_rewrite r on (r.oid = dep.objid)
    join pg_class o on (o.oid = r.ev_class)
    where r.ev_class <> dep.refobjid
    and dep.classid = 'pg_rewrite'::regclass
    and dep.refclassid = 'pg_class'::regclass
    and o.relkind = 'v'
),
view_dep (f, t) as (
    select view_oid, ref_oid
    from view_ref
    where exists (select from pg_class c where c.oid = ref_oid and c.relkind = 'v')
),
-- create or replace view cannot rename or retype existing output columns, but
-- it can append new ones; only a prefix mismatch requires an actual drop
view_cols_shadow (nspname, relname, cols) as (
    select n.nspname, c.relname,
           array_agg(a.attname::text || ':' || a.format_type order by a.attnum)
    from shadow_catalog.pg_class c
    join shadow_catalog.pg_namespace n on (n.oid = c.relnamespace)
    join shadow_catalog.pg_attribute_fdw a on (a.attrelid = c.oid)
    where c.relkind = 'v' and a.attnum > 0 and not a.attisdropped
    and not exists (select from shadow.excluded_schema e where e.nspname = n.nspname)
    group by n.nspname, c.relname
),
view_cols_current (nspname, relname, cols) as (
    select n.nspname, c.relname,
           array_agg(a.attname::text || ':' || pg_catalog.format_type(a.atttypid, a.atttypmod) order by a.attnum)
    from pg_class c
    join pg_namespace n on (n.oid = c.relnamespace)
    join pg_attribute a on (a.attrelid = c.oid)
    where c.relkind = 'v' and a.attnum > 0 and not a.attisdropped
    and not exists (select from shadow.excluded_schema e where e.nspname = n.nspname)
    group by n.nspname, c.relname
),
view_cols_changed (nspname, relname) as (
    select d.nspname, d.relname
    from view_cols_current d
    join view_cols_shadow s using (nspname, relname)
    where d.cols[1:cardinality(s.cols)] collate "C" <> s.cols collate "C"
),
changed_tables (nspname, relname) as (
    select distinct schema, rel
    from shadow.column_diff
),
affected_direct (oid) as (
    select distinct r.view_oid
    from view_ref r
    join pg_class c on (c.oid = r.ref_oid)
    join pg_namespace n on (n.oid = c.relnamespace)
    join changed_tables t on (t.nspname, t.relname) = (n.nspname, c.relname)
    where c.relkind in ('r', 'p')
    union
    select d.oid
    from view_current d
    join view_cols_changed c using (nspname, relname)
),
-- views directly on changed tables plus everything stacked on top of them
affected (oid) as (
    select oid from affected_direct
    union
    select d.f
    from view_dep d
    join affected a on (d.t = a.oid)
),
-- priority is the number of views stacked on a view: base views first when
-- creating, dependents first when dropping
view_depth (oid, depth) as (
    select oid, 0 from view_current
    union
    select d.f, depth + 1
    from view_depth v
    join view_dep d on (d.t = v.oid)
),
view_priority (oid, priority) as (
    select oid, max(depth) from view_depth group by oid
),
view_to_add as (
    select d.*
    from view_current d
    full outer join view_shadow t using (nspname, relname)
    where t.relname is null or d.def <> t.def
),
view_to_recreate as (
    select d.*
    from view_current d
    where exists (select from view_to_add a where a.oid = d.oid)
    or exists (select from affected a where a.oid = d.oid)
),
view_to_drop as (
    select *
    from view_shadow t
    where not exists (select from view_current d where (d.nspname, d.relname) = (t.nspname, t.relname))
)
select v.nspname, v.oid, v.relname, v.def, false, p.priority,
       a.oid is not null and exists (
           select from view_shadow s where (s.nspname, s.relname) = (v.nspname, v.relname)
       )
from view_to_recreate v
left join view_priority p on (p.oid = v.oid)
left join affected a on (a.oid = v.oid)
union all
select nspname, null::oid, relname, def, true, null::int, false
from view_to_drop
order by 5 desc, 6 nulls first
;

drop view if exists shadow.privilege_diff cascade;
create view shadow.privilege_diff (
    schema, privilege, type, "on", "to", drop
)
as
-- ACLs are expanded on the target side via shadow_catalog.pg_class_acl_fdw:
-- aclitem text cannot be parsed locally when target roles do not exist here.
-- Unchanged privileges on a view that will be dropped and recreated still have
-- to be granted: dropping the view throws away its ACL.
with shadow (nspname, privilege_type, objtype, relname, rolname) as (
    select nspname, privilege_type, 'table', relname, rolname
    from shadow_catalog.pg_class_acl_fdw a
    where not exists (select from shadow.excluded_schema e where e.nspname = a.nspname)
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = a.oid)
),
current (nspname, privilege_type, objtype, relname, rolname) as (
    select nspname, privilege_type, 'table', c.relname, r.rolname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace s on (s.oid = c.relnamespace)
    , aclexplode(coalesce(
        c.relacl,
        acldefault(case when c.relkind = 'S' then 'S'::"char" else 'r'::"char" end, c.relowner)
    )) acl
    join pg_catalog.pg_authid r on r.oid = acl.grantee
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and c.relkind in ('r', 'p', 'v', 'm', 'S')
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_class'::regclass and e.objid = c.oid)
),
diff as (
    select *, current is null as is_drop, current as current_row, shadow as shadow_row
    from shadow
    natural full outer join current
)
select nspname, privilege_type, objtype, relname, rolname, is_drop
from diff
where current_row is distinct from shadow_row
or (current_row is not null and exists (
    select from shadow.view_diff v
    where v.drop_first and not v.drop
    and (v.schema, v.rel) = (nspname, relname)
))
;

drop view if exists shadow.routine_diff cascade;
create view shadow.routine_diff (
    schema, name, def, args, drop, add
)
as
-- Function definitions and identity arguments are generated on the target side
-- via shadow_catalog.pg_proc_fdw; foreign pg_proc oids cannot be passed to
-- pg_get_functiondef() locally. Dropping is only needed when the identity
-- (args) or result type changes; otherwise CREATE OR REPLACE suffices.
with shadow (nspname, proname, def, args, result, prokind) as (
    select nspname, proname, p.pg_get_functiondef, p.args, p.result, p.prokind
    from shadow_catalog.pg_proc_fdw p
    join shadow_catalog.pg_namespace s on (s.oid = p.pronamespace)
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and prokind <> 'a'
    and not exists (select from shadow_catalog.extension_objects e where e.classid = 'pg_catalog.pg_proc'::regclass and e.objid = p.oid)
),
current (nspname, proname, def, args, result, prokind) as (
    select nspname, proname, pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid), p.prokind
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace s on (s.oid = p.pronamespace)
    where not exists (select from shadow.excluded_schema e where e.nspname = s.nspname)
    and prokind <> 'a'
    and not exists (select from shadow.extension_objects e where e.classid = 'pg_catalog.pg_proc'::regclass and e.objid = p.oid)
)
select coalesce(shadow.nspname, current.nspname),
       coalesce(shadow.proname, current.proname),
       coalesce(current.def, shadow.def),
       coalesce(current.args, shadow.args),
       current is null or (
           current is not null and shadow is not null
           and current.result collate "C" <> shadow.result collate "C"
       ),
       shadow is null or (
           current is not null and shadow is not null
           and (current.def collate "C" <> shadow.def collate "C"
                or current.result collate "C" <> shadow.result collate "C")
       )
from shadow
full join current using (nspname, proname, args, prokind)
where (current is null or shadow is null
       or current.def collate "C" <> shadow.def collate "C"
       or current.result collate "C" <> shadow.result collate "C")
and not exists (
    select from shadow.schema_diff to_d
    where to_d.drop and to_d.nspname = coalesce(shadow.nspname, current.nspname)
)
;

drop function if exists shadow.alter_ddl;
create or replace function shadow.alter_ddl(if_exists text default ' if exists', cascade text default ' cascade')
returns setof text
language sql
volatile parallel safe
begin atomic
-- Each diff is evaluated once here; without the CTEs it would be rescanned
-- once per branch below (and column/constraint diffs are used three times).
with
schemas as (select * from shadow.schema_diff),
types as (select * from shadow.type_diff),
domains as (select * from shadow.domain_diff),
tables as (select * from shadow.table_diff),
columns as (select * from shadow.column_diff),
policies as (select * from shadow.policy_diff),
indexes as (select * from shadow.index_diff),
constraints as (select * from shadow.constraint_diff),
views as (select * from shadow.view_diff),
routines as (select * from shadow.routine_diff),
privileges as (select * from shadow.privilege_diff)
select format('drop schema%s %I%s;', if_exists, nspname, cascade)
from schemas
where drop

union all
select format('drop view%s %I.%I%s;', if_exists, schema, rel, cascade)
from views
where drop

union all
(select format('drop view%s %I.%I%s;', if_exists, schema, rel, cascade)
from views
where drop_first
order by priority desc nulls first)

union all
select format('drop routine%s %I.%I (%s)%s;', if_exists, schema, name, args, cascade)
from routines
where drop

union all
select format('drop index%s %I.%I%s;', if_exists, schema, index, cascade)
from indexes
where drop

union all
select format('drop table%s %I.%I%s;', if_exists, schema, rel, cascade)
from tables
where drop

union all
select format('alter table %I.%I drop column%s %I;', schema, rel, if_exists, attname)
from columns
where drop

union all
select format('drop domain%s %I.%I%s;', if_exists, schema, name, cascade)
from domains
where drop

union all
select format('drop type%s %I.%I%s;', if_exists, schema, name, cascade)
from types
where drop

union all
select format('create schema %I;', nspname)
from schemas
where not drop

union all
select format('create type %I.%I as %s;', schema, name::text, case typtype
    when 'e' then format('enum (%s)', array_to_string(array(
        select quote_literal(enumlabel)
        from pg_enum
        where enumtypid = t.oid::oid
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
from types t
where not drop

union all
select format('create domain %I.%I as %s', schema, name, def)
from domains
where not drop

union all
select format('create table %I.%I ();', schema, rel)
from tables
where not drop

union all
select format('alter table %I.%I add column %I %s%s%s;',
    schema,
    rel,
    attname,
    current_type,
    case when current_not_null then ' not null' else '' end,
    case
        when current_expr <> '' and current_attgenerated = ''
            then format(' default %s', current_expr)
        when current_expr <> '' and current_attgenerated <> ''
            then format(' generated always as (%s) %s',
                current_expr,
                case current_attgenerated when 's' then 'stored' when 'v' then 'virtual' end
            )
        when current_attidentity <> ''
            then format(' generated %s as identity',
                case current_attidentity when 'a' then 'always' when 'd' then 'by default' end
            )
        else ''
    end
)
from columns
where add

union all
select format('alter table %I.%I alter column %I %s;', schema, rel, attname, action)
from columns,
lateral (values
    (
        format('type %s', current_type),
        current_type <> shadow_type
    ),
    (
        format('set default %s', current_expr),
        current_expr <> shadow_expr and current_expr <> '' and current_attgenerated = ''
    ),
    (
        'drop default',
        current_expr <> shadow_expr and current_expr = '' and current_attgenerated = ''
    ),
    (
        format('set expression as (%s)', current_expr),
        current_expr <> shadow_expr and current_expr <> '' and current_attgenerated <> ''
    ),
    (
        'drop expression',
        current_expr <> shadow_expr and current_expr = '' and current_attgenerated <> ''
    ),
    (
        format('add generated %s as identity', case current_attidentity when 'a' then 'always' when 'd' then 'by default' end),
        current_attidentity <> shadow_attidentity and shadow_attidentity = ''
    ),
    (
        format('set generated %s', case current_attidentity when 'a' then 'always' when 'd' then 'by default' end),
        current_attidentity <> shadow_attidentity and current_attidentity <> '' and shadow_attidentity <> ''
    ),
    (
        'drop identity',
        current_attidentity <> shadow_attidentity and current_attidentity = ''
    ),
    (
        'set not null',
        current_not_null <> shadow_not_null and current_not_null
    ),
    (
        'drop not null',
        current_not_null <> shadow_not_null and not current_not_null
    )
) _ (action, applies)
where not drop and not add and applies

union all
select format('%s;', def)
from indexes
where not drop

union all
select format('alter table %I.%I drop constraint%s %I%s;', schema, rel, if_exists, name, cascade)
from constraints
where not add

union all
(select format('alter table %I.%I add constraint %I %s;', schema, rel, name, current_def)
from constraints
where not drop
order by case current_type when 'p' then 1 when 'u' then 2 end nulls last)

union all
select format('alter table %I.%I alter constraint %I %s%s;', schema, rel, name,
    case when current_is_deferrable then 'deferrable' else 'not deferrable' end,
    case when current_is_deferred then ' initially deferred' else ' initially immediate' end
)
from constraints
where not drop and not add
and (current_is_deferrable <> shadow_is_deferrable
or current_is_deferred <> shadow_is_deferred)

union all
select format('%s;', def)
from routines
where add

union all
(select format('create or replace view %I.%I as %s', schema, rel, def)
from views
where not drop
order by priority nulls first)

union all
select format('drop policy%s %I on %I.%I%s;', if_exists, policyname, schemaname, tablename, cascade)
from policies
where drop

union all
select format('create policy %I on %I.%I as %s for %s to %s%s%s;',
    policyname, schemaname, tablename,
    current_permissive,
    current_cmd,
    concat_ws(', ', variadic current_roles),
    case when current_qual is not null then format(' using (%s)', current_qual) end,
    case when current_with_check is not null then format(' with check (%s)', current_with_check) end
)
from policies
where not drop

union all
select format('revoke %s on %s %I.%I from %s;', privilege, type, schema, "on", "to")
from privileges
where drop

union all
select format('grant %s on %s %I.%I to %s;', privilege, type, schema, "on", "to")
from privileges
where not drop
;
end;
