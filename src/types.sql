set search_path to pgdiff;

drop type if exists ddl_type cascade;
create type ddl_type as enum (
    'create schema',
    'drop type',
    'create type',
    'drop domain',
    'create domain',
    'drop routine',
    'create routine',
    'drop table',
    'drop index',
    'create table',
    'rename table',
    'rename column',
    'drop column',
    'add column',
    'add constraint',
    'alter constraint',
    'drop constraint',
    'alter column set default',
    'alter column drop default',
    'alter column drop not null',
    'alter column set not null',
    'alter column type',
    'create index'
);

drop type if exists _alteration cascade;
create type _alteration as (
    "order" int, -- smaller number means higher priority
    type ddl_type,
    ddl text,
    details jsonb
);

drop domain if exists alteration cascade;
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
    when 'add column' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'column_name' and
        (value).details ? 'is_nullable' and
        (value).details ? 'column_default' and
        (value).details ? 'data_type'
    when 'add constraint' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'constraint_name'
    when 'alter constraint' then
        (value).details ? 'schema_name' and
        (value).details ? 'table_name' and
        (value).details ? 'constraint_name' and
        (value).details ? 'deferrable' and
        (value).details ? 'deferred'
    when 'drop constraint' then
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
    when 'create routine' then
        (value).details ? 'schema_name' and
        (value).details ? 'routine_name'
    when 'drop routine' then
        (value).details ? 'schema_name' and
        (value).details ? 'routine_name'
    when 'create type' then
        (value).details ? 'schema_name' and
        (value).details ? 'type_name'
    when 'drop type' then
        (value).details ? 'schema_name' and
        (value).details ? 'type_name'
    when 'create domain' then
        (value).details ? 'schema_name' and
        (value).details ? 'domain_name'
    when 'drop domain' then
        (value).details ? 'schema_name' and
        (value).details ? 'domain_name'
    else false
end));
