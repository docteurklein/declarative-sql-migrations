\set ON_ERROR_STOP on

create extension if not exists postgres_fdw;

create server if not exists :desired foreign data wrapper postgres_fdw options (dbname :'desired');

create user mapping if not exists for current_user server :desired;

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
from server :desired
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
server :desired
options (schema_name 'pg_catalog', table_name 'pg_attribute');

create foreign table shadow.pg_attrdef (
    oid oid not null,
    adrelid oid not null,
    adnum smallint not null,
    expr text not null
)
server :desired
options (schema_name 'fdw_catalog', table_name 'pg_attrdef');
