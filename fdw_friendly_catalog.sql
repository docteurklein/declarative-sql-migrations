drop schema if exists fdw_friendly_catalog cascade;
create schema fdw_friendly_catalog;

create view fdw_friendly_catalog.pg_attribute_fdw as
select attrelid, attname, atttypid, attlen, attnum, atttypmod, attndims, attbyval, attalign, attstorage, attcompression, attnotnull, atthasdef, atthasmissing, attidentity, 
attgenerated, attisdropped, attislocal, attinhcount, attcollation, attstattarget, attacl , attoptions, attfdwoptions,
format_type(atttypid, atttypmod) collate "C"
from pg_catalog.pg_attribute;

create view fdw_friendly_catalog.pg_attrdef_fdw as
select *, pg_get_expr(adbin, adrelid, true) collate "C" expr
from pg_catalog.pg_attrdef;


create view fdw_friendly_catalog.pg_type_fdw as
select *, format_type(oid, typtypmod) collate "C"
from pg_catalog.pg_type;

create view fdw_friendly_catalog.pg_constraint_fdw as
select *, pg_get_constraintdef(oid) collate "C" pg_get_constraintdef
from pg_catalog.pg_constraint;

create view fdw_friendly_catalog.pg_proc_fdw as
select *,
       case when prokind <> 'a' then pg_get_functiondef(oid) end collate "C" pg_get_functiondef,
       case when prokind <> 'a' then pg_get_function_identity_arguments(oid) end collate "C" args,
       case when prokind <> 'a' then pg_get_function_result(oid) end collate "C" result
from pg_catalog.pg_proc;

create view fdw_friendly_catalog.pg_class_acl_fdw as
select c.oid, n.nspname, c.relname, c.relkind,
       acl.privilege_type, acl.is_grantable, grantee.rolname
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on (n.oid = c.relnamespace)
, aclexplode(coalesce(
    c.relacl,
    acldefault(case when c.relkind = 'S' then 'S'::"char" else 'r'::"char" end, c.relowner)
)) acl
join pg_catalog.pg_authid grantee on (grantee.oid = acl.grantee)
where c.relkind in ('r', 'p', 'v', 'm', 'S');

create view fdw_friendly_catalog.extension_objects as
select classid, objid
from pg_catalog.pg_depend
where refclassid = 'pg_catalog.pg_extension'::regclass
and deptype = 'e';

