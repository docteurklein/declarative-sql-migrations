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
    -- 'create trigger',
    -- 'alter function',
    -- 'alter procedure',
    -- 'alter trigger',
    'create table',
    'add column',
    'alter table add constraint',
    'alter table alter constraint',
    'alter table drop constraint',
    'alter column set default',
    'alter column drop default',
    'alter column drop not null',
    'alter column set not null',
    'alter column type',
    -- 'add primary key',
    -- 'add foreign key',
    -- 'drop primary key',
    -- 'drop foreign key',
    'create index',
    -- 'create view',
    'drop index',
    -- 'drop view',
    'drop table',
    'drop column'
    -- 'drop function',
    -- 'drop procedure',
    -- 'drop trigger',
    -- 'drop type'
);

create type alteration as (
    "order" int, -- smaller number means higher priority
    type ddl_type,
    details jsonb
);

create function exec(inout ddl text)
language plpgsql strict parallel safe
as 'begin execute ddl; end;';

create function ddl(
    alteration alteration,
    cascade bool default false
) returns text
language sql strict immutable parallel safe as $$
    -- select row_to_json(alteration);
    select case alteration.type
        -- when 'create type'
        -- when 'alter type'
        -- when 'create function'
        -- when 'create procedure'
        -- when 'alter function'
        -- when 'alter procedure'
        when 'create schema'
            then format('create schema %I',
                alteration.details->>'schema_name'
            )
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
        when 'alter table add constraint'
            then format('alter table %I.%I add constraint %s %s',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'constraint_name',
                alteration.details->>'ddl'
            )
        when 'alter table alter constraint'
            then format('alter table %I.%I alter constraint %s %s %s',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'constraint_name',
                case (alteration.details->>'deferrable')::bool
                    when true then 'deferrable'
                    else 'not deferrable'
                end,
                case (alteration.details->>'deferred')::bool
                    when true then 'initially deferred'
                    else 'initially immediate'
                end
            )
        when 'alter table drop constraint'
            then format('alter table %I.%I drop constraint %s',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'constraint_name'
            )
        when 'create index'
            then alteration.details->>'ddl'
        when 'drop index'
            then format(
                'drop index %I.%I',
                alteration.details->>'schema_name',
                alteration.details->>'index_name'
            )
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

-- create function table_to_drop(desired text, target text) returns setof alteration
-- language sql as $$
--     select 1, 'drop table'::ddl_type, jsonb_build_object(
--         'schema_name', target,
--         'table_name', tablename
--     ) from pg_tables
--     where schemaname = target
--     except
--     select 1, 'drop table'::ddl_type, jsonb_build_object(
--         'schema_name', target,
--         'table_name', tablename
--     ) from pg_tables
--     where schemaname = desired
-- $$;


create function alterations(desired text, target text) returns setof alteration
language plpgsql strict parallel safe as $$
declare
    alteration alteration;
begin
    for alteration in
        with schema_to_create as (
            select 0, 'create schema', jsonb_build_object(
                'schema_name', target
            ) from pg_namespace
            where not exists (
                select from pg_namespace where nspname = target
            )
        ),
        table_to_create as (
            select 1, 'create table', jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = desired
            except
            select 1, 'create table', jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = target
        ),
        table_to_drop as (
            select 7, 'drop table', jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = target
            except
            select 7, 'drop table', jsonb_build_object(
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
            select 2, 'add column', jsonb_build_object(
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
            select 6, 'drop column', jsonb_build_object(
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
            select d.*,
                d.is_nullable != t.is_nullable as nullable_changed,
                d.column_default != t.column_default as default_changed,
                d.data_type != t.data_type as type_changed
            from information_schema.columns d
            join information_schema.columns t using(table_name, column_name)
            where t.table_schema = target
            and d.table_schema = desired
            and not exists (
                select from column_to_add
                where table_name = d.table_name
                and column_name = d.column_name
            )
        ),
        column_set_default as (
            select 3, 'alter column set default', jsonb_build_object(
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
            select 3, 'alter column drop default', jsonb_build_object(
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
            select 3, 'alter column drop not null', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'is_nullable', is_nullable::bool
            )
            from column_to_alter
            where nullable_changed
            and is_nullable::bool
        ),
        column_set_not_null as (
            select 3, 'alter column set not null', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'is_nullable', is_nullable::bool
            )
            from column_to_alter
            where nullable_changed
            and not is_nullable::bool
        ),
        column_type as (
            select 3, 'alter column type', jsonb_build_object(
                'schema_name', target,
                'table_name', table_name,
                'column_name', column_name,
                'data_type', data_type
            )
            from column_to_alter
            where type_changed
        ),
        constraint_to_create as (
            with missing as (
                select dcl.relname, dc.conname, dc.oid, dc.contype
                from pg_constraint dc
                join pg_class dcl on dcl.oid = dc.conrelid
                left join pg_constraint tc on tc.conname = dc.conname and tc.connamespace = to_regnamespace(target)::oid
                where tc.oid is null
                and dc.contype in ('f', 'p', 'c', 'u')
                and dc.connamespace = desired::regnamespace 
            )
            select 
                case contype when 'p' then 4 else 5 end, -- primary key first
                'alter table add constraint',
                jsonb_build_object(
                    'schema_name', target,
                    'constraint_name', conname,
                    'table_name', relname,
                    'ddl', replace(pg_get_constraintdef(oid), desired || '.', target || '.' -- bad
                )
            ) from missing
        ),
        constraint_to_alter as (
            with different as (
                select dcl.relname, dc.conname, dc.condeferrable, dc.condeferred
                from pg_constraint dc
                join pg_class dcl on dcl.oid = dc.conrelid
                left join pg_constraint tc on tc.conname = dc.conname and tc.connamespace = to_regnamespace(target)::oid
                where (
                    tc.condeferred != dc.condeferred
                    or tc.condeferrable != dc.condeferrable
                )
                and dc.contype in ('f') -- only fkeys are supported
                and dc.connamespace = desired::regnamespace 
            )
            select 5, 'alter table alter constraint', jsonb_build_object(
                'schema_name', target,
                'constraint_name', conname,
                'table_name', relname,
                'deferrable', condeferrable::bool,
                'deferred', condeferred::bool
            ) from different
        ),
        constraint_to_drop as (
            with extra as (
                select dcl.relname, dc.conname
                from pg_constraint dc
                join pg_class dcl on dcl.oid = dc.conrelid
                left join pg_constraint tc on tc.conname = dc.conname and tc.connamespace = desired::regnamespace::oid
                where tc.oid is null
                and dc.contype in ('f', 'p', 'c', 'u')
                and dc.connamespace = to_regnamespace(target)
            )
            select 4, 'alter table drop constraint', jsonb_build_object(
                'schema_name', target,
                'constraint_name', conname,
                'table_name', relname
            ) from extra
        ),
        index_to_create as (
            with missing as (
                select dc.relname, di.indrelid::regclass, di.indexrelid
                from pg_index di
                join pg_class dc on di.indexrelid = dc.oid and dc.relnamespace = desired::regnamespace::oid
                left join pg_class tc on tc.relname = dc.relname and tc.relnamespace = to_regnamespace(target)::oid
                where tc.oid is null
                and not di.indisprimary
                and not di.indisunique
            )
            select 6, 'create index', jsonb_build_object(
                'schema_name', target,
                'index_name', relname,
                'table_name', indrelid,
                'ddl',  replace(pg_get_indexdef(indexrelid), desired || '.', target || '.') -- bad
            ) from missing
        ),
        index_to_drop as (
            with extra as (
                select tc.relname, ti.indrelid::regclass
                from pg_index ti
                join pg_class tc on ti.indexrelid = tc.oid and tc.relnamespace = to_regnamespace(target)::oid
                left join pg_class dc on dc.relname = tc.relname and dc.relnamespace = desired::regnamespace::oid
                where dc.oid is null
                and not ti.indisprimary
                and not ti.indisunique
            )
            select 6, 'drop index', jsonb_build_object(
                'schema_name', target,
                'index_name', relname,
                'table_name', indrelid
            )
            from extra
        )
        table schema_to_create union
        table table_to_create union
        table table_to_drop union
        table column_to_add union
        table column_to_drop union
        table column_set_default union
        table column_drop_default union
        table column_drop_not_null union
        table column_set_not_null union
        table constraint_to_create union
        table constraint_to_alter union
        table constraint_to_drop union
        table index_to_create union
        table index_to_drop union
        table column_type
        order by 1
    loop
        return next alteration;
    end loop;
end;
$$;

create procedure migrate(
    desired text,
    target text,
    dry_run bool default true,
    keep_data bool default false,
    cascade bool default false
)
language plpgsql as $$
declare
    alteration text;
begin
    for alteration in
        select ddl(a, cascade) from alterations(desired, target) a
        where case when keep_data is true
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
