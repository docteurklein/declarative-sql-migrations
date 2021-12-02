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

create type _alteration as (
    "order" int, -- smaller number means higher priority
    type ddl_type,
    ddl text,
    details jsonb
);

create domain alteration as _alteration
constraint valid check (
value is null or (
(value)."order" is not null
and (value).type is not null
and case (value).type
    when 'create schema' then
        (value).details ? 'schema_name'
    when 'create table' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name'
    when 'alter table add column' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name' and
        (value).details ? 'is_nullable' and
        (value).details ? 'column_default' and
        (value).details ? 'data_type'
    when 'alter table add constraint' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'constraint_name'
    when 'alter table alter constraint' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'constraint_name' and
        (value).details ? 'deferrable' and
        (value).details ? 'deferred'
    when 'alter table drop constraint' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'constraint_name'
    when 'alter column set default' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name' and
        (value).details ? 'column_default'
    when 'alter column drop default' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name' and
        (value).details ? 'column_default'
    when 'alter column drop not null' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name' and
        (value).details ? 'is_nullable'
    when 'alter column set not null' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name' and
        (value).details ? 'is_nullable'
    when 'alter column type' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name' and
        (value).details ? 'data_type'
    when 'create index' then
        (value).details ? 'schema_name' and
        (value).details ? 'index_name' and
        (value).details ? 'table_name'
    when 'drop index' then
        (value).details ? 'schema_name' and
        (value).details ? 'index_name' and
        (value).details ? 'table_name'
    when 'drop table' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'cascade'
    when 'drop column' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name'
    else false
end));

\i src/alterations.sql
\i src/exec.sql
\i src/migrate.sql

commit;
