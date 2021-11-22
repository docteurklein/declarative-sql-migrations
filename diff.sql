begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

set search_path to pgdiff;

create type ddl_type as enum (
    'create schema',
    -- 'create type',
    -- 'alter type',
    -- 'create function',
    -- 'create procedure',
    -- 'alter function',
    -- 'alter procedure',
    'create table',
    'add column',
    'alter column set default',
    'alter column drop default',
    'alter column drop not null',
    'alter column set not null',
    'alter column type',
    -- 'add primary key',
    -- 'add foreign key',
    -- 'drop primary key',
    -- 'drop foreign key',
    -- 'create index',
    -- 'create view',
    -- 'drop index',
    -- 'drop view',
    'drop table',
    'drop column'
    -- 'drop function',
    -- 'drop procedure',
    -- 'drop type'
);

create type alteration as (
    type ddl_type,
    details jsonb
);

create function ddl(
    alteration alteration,
    cascade bool default false
) returns text
language sql strict immutable parallel safe as $$
    -- select row_to_json(alteration);
    select case alteration.type
        when 'create schema'
            then format('create schema %I', alteration.details->>'schema_name')
        -- when 'create type'
        -- when 'alter type'
        -- when 'create function'
        -- when 'create procedure'
        -- when 'alter function'
        -- when 'alter procedure'
        when 'create table'
            then format('create table %I.%I ()',
                alteration.details->>'schema_name',
                alteration.details->>'table_name'
            )
        when 'add column'
            then format(
                'alter table %I.%I add column %I %s %s %s',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name',
                alteration.details->>'data_type',
                case (alteration.details->>'is_nullable')::bool
                    when true then ''
                    else 'not null'
                end,
                case when alteration.details->>'column_default' is not null
                    then format('default %s', alteration.details->>'column_default')
                    else ''
                end
            )
        when 'alter column set default'
            then format(
                'alter table %I.%I alter column %I set default %s',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name',
                alteration.details->>'column_default'
            )
        when 'alter column drop default'
            then format(
                'alter table %I.%I alter column %I drop default',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name'
            )
        when 'alter column drop not null'
            then format(
                'alter table %I.%I alter column %I drop not null',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name'
            )
        when 'alter column set not null'
            then format(
                'alter table %I.%I alter column %I set not null',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name'
            )
        when 'alter column type'
            then format(
                'alter table %I.%I alter column %I type %s',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name',
                alteration.details->>'data_type'
            )
        -- when 'create index'
        -- when 'drop index'
        when 'drop column'
            then format(
                'alter table %I.%I drop column %I',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name'
            )
        when 'drop table'
            then format('drop table %I.%I %s',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                case cascade when true then 'cascade' else '' end
            )
        -- when 'drop function'
        -- when 'drop procedure'
        -- when 'drop type'
        else ''
    end;
$$;

create function alterations(desired text, target text) returns setof alteration
language plpgsql as $$
declare
    alteration record;
begin
    for alteration in
        with schema_to_create as (
            select 'create schema', jsonb_build_object(
                'schema_name', target
            ) from pg_namespace
            where nspname = desired
            except
            select 'create schema', jsonb_build_object(
                'schema_name', target
            ) from pg_namespace
            where nspname = target
        ),
        table_to_create as (
            select 'create table', jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = desired
            except
            select 'create table', jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = target
        ),
        table_to_drop as (
            select 'drop table', jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = target
            except
            select 'drop table', jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = desired
        ),
        column_to_add as (
            with missing as (
                select table_name, column_name -- compare only those two with "except", because "ordinal_position" can be always different
                from information_schema.columns
                where table_schema = desired
                except
                select table_name, column_name
                from information_schema.columns
                where table_schema = target
            )
            select 'add column', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'is_nullable', is_nullable,
                'column_default', column_default,
                'data_type', data_type
            )
            from information_schema.columns
            join missing using (table_name, column_name)
            where table_schema = desired
            order by table_name, ordinal_position asc
        ),
        column_to_drop as (
            with extra_column as (
                select table_name, column_name
                from information_schema.columns
                where table_schema = target
                except
                select table_name, column_name
                from information_schema.columns
                where table_schema = desired
            )
            select 'drop column', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name
            )
            from extra_column
            where not exists (
                select from table_to_drop
                where table_name = table_name
            )
        ),
        column_to_alter as (
            with different_column as (
                select table_name, column_name, is_nullable, data_type, column_default
                from information_schema.columns
                where table_schema = desired
                except
                select table_name, column_name, is_nullable, data_type, column_default
                from information_schema.columns
                where table_schema = target
            )
            select desired.*,
                desired.is_nullable != t.is_nullable as nullable_changed,
                desired.column_default != t.column_default as default_changed,
                desired.data_type != t.data_type as type_changed
            from different_column desired
            join information_schema.columns t using(table_name, column_name)
            where t.table_schema = target
            and not exists (
                select from column_to_add
                where table_name = desired.table_name
                and column_name = desired.column_name
            )
        ),
        column_set_default as (
            select 'alter column set default', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'column_default', column_default
            )
            from column_to_alter
            where default_changed
            and column_default is not null
        ),
        column_drop_default as (
            select 'alter column drop default', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'column_default', column_default
            )
            from column_to_alter
            where default_changed
            and column_default is null
        ),
        column_drop_not_null as (
            select 'alter column drop not null', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'is_nullable', is_nullable
            )
            from column_to_alter
            where nullable_changed
            and is_nullable::bool
        ),
        column_set_not_null as (
            select 'alter column set not null', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'is_nullable', is_nullable
            )
            from column_to_alter
            where nullable_changed
            and not is_nullable::bool
        ),
        column_type as (
            select 'alter column type', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'data_type', data_type
            )
            from column_to_alter
            where type_changed
        )
        select 1, a::alteration from (table schema_to_create)      a union
        select 2, a::alteration from (table table_to_create)       a union
        select 3, a::alteration from (table table_to_drop)         a union
        select 4, a::alteration from (table column_to_add)         a union
        select 5, a::alteration from (table column_to_drop)        a union
        select 6, a::alteration from (table column_set_default)    a union
        select 7, a::alteration from (table column_drop_default)   a union
        select 8, a::alteration from (table column_drop_not_null)  a union
        select 9, a::alteration from (table column_set_not_null)   a union
        select 10, a::alteration from (table column_type) a
        order by 1
    loop
        return next alteration.a;
    end loop;
end;
$$;

create procedure migrate(
    desired text,
    target text,
    dry_run bool default true,
    keep_extra bool default false,
    cascade bool default false
)
language plpgsql as $$
declare
    alteration text;
begin
    for alteration in
        select ddl(a, cascade) from alterations(desired, target) a
        where case when keep_extra is true
            then type not in ('drop table', 'drop column')
            else true
            end
    loop
        raise notice '%', alteration;
        if dry_run is false
            then execute alteration;
            else null;
        end if;
    end loop;
end;
$$;

commit;
