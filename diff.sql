begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

set search_path to pgdiff;

create type ddl_type as enum (
    'create schema',
    'create table',
    'alter table add column',
    'alter table add constraint',
    'alter table alter constraint',
    'alter table drop constraint',
    'alter column set default',
    'alter column drop default',
    'alter column drop not null',
    'alter column set not null',
    'alter column type',
    'create index',
    'drop index',
    'drop table',
    'drop column'
);
create cast (text as ddl_type) with inout as implicit;

create type alteration as (
    "order" int, -- smaller number means higher priority
    type ddl_type,
    ddl text,
    details jsonb
);

\i src/alterations.sql
\i src/exec.sql
\i src/migrate.sql

commit;
