drop schema if exists fdw_friendly_catalog cascade;
create schema fdw_friendly_catalog;

create view fdw_friendly_catalog.pg_attribute_fdw as
select attrelid, attname, atttypid, attlen, attnum, atttypmod, attndims, attbyval, attalign, attstorage, attcompression, attnotnull, atthasdef, atthasmissing, attidentity, 
attgenerated, attisdropped, attislocal, attinhcount, attcollation, attstattarget, attacl , attoptions, attfdwoptions,
format_type(atttypid, atttypmod) collate "C" formatted_type
from pg_catalog.pg_attribute;

create view fdw_friendly_catalog.pg_attrdef_fdw as
select *, pg_get_expr(adbin, adrelid, true) collate "C" expr
from pg_catalog.pg_attrdef;


create view fdw_friendly_catalog.pg_type_fdw as
select *, format_type(oid, typtypmod) collate "C" formatted_type
from pg_catalog.pg_type;
