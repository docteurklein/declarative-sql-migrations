drop schema if exists fdw_catalog cascade;
create schema fdw_catalog;

create view fdw_catalog.pg_attrdef as
select *, pg_get_expr(adbin, adrelid, true) expr
from pg_catalog.pg_attrdef;

