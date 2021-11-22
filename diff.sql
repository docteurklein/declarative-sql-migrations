begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

set search_path to pgdiff;

create type ddl_type as enum (
    'create schema',
    'create type',
    'alter type',
    'create function',
    'create procedure',
    'alter function',
    'alter procedure',
    'create table',
    'add column',
    'alter column set default',
    'alter column drop default',
    'alter column drop not null',
    'alter column set not null',
    'alter column type',
    'create index',
    'alter index',
    'drop index',
    'drop column',
    'drop table',
    'drop function',
    'drop procedure',
    'drop type'
);

create type alteration as (
    type ddl_type,
    details jsonb
);

create function ddl(alteration alteration) returns text
language sql immutable parallel safe as $$
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
        -- when 'alter index'
        -- when 'drop index'
        when 'drop column'
            then format(
                'alter table %I.%I drop column %I',
                alteration.details->>'schema_name',
                alteration.details->>'table_name',
                alteration.details->>'column_name'
            )
        when 'drop table'
            then format('drop table %I.%I',
                alteration.details->>'schema_name',
                alteration.details->>'table_name'
            )
        -- when 'drop function'
        -- when 'drop procedure'
        -- when 'drop type'
        else ''
    end from (select alteration) _(alteration);
$$;

create function exec(inout ddl text, dry_run bool default true) returns text
language plpgsql as $$
begin
    raise notice '%', ddl;
    if not dry_run then
        execute ddl;
    end if;
end
$$;

create function alterations(desired text, target text) returns setof alteration
language plpgsql as $$
declare
    missing_table record;
    extra_table record;
    missing_column record;
    extra_column record;
    different_column record;
    missing_index record;
    different_index record;
begin
    if not exists(
        select schema_name from information_schema.schemata
        where schema_name = target
    ) then
        return next row(
            'create schema',
            jsonb_build_object(
                'schema_name', target
            )
        )::alteration;
    end if;
    for missing_table in
        select table_name from information_schema.tables
        where (table_schema, table_type) = (desired, 'BASE TABLE')
        except
        select table_name from information_schema.tables
        where (table_schema, table_type) = (target, 'BASE TABLE')
    loop
        return next row(
            'create table',
            jsonb_build_object(
                'schema_name', target,
                'table_name', missing_table.table_name
            )
        )::alteration;
    end loop;

    for extra_table in
        select table_name from information_schema.tables
        where (table_schema, table_type) = (target, 'BASE TABLE')
        except
        select table_name from information_schema.tables
        where (table_schema, table_type) = (desired, 'BASE TABLE')
    loop
        return next row(
            'drop table',
            jsonb_build_object(
                'schema_name', target,
                'table_name', extra_table.table_name
            )
        )::alteration;
    end loop;

    for missing_column in
        with missing as (
            select table_name, column_name
            from information_schema.columns
            where table_schema = desired
            except
            select table_name, column_name
            from information_schema.columns
            where table_schema = target
        )
        select table_name, column_name, is_nullable, data_type, ordinal_position, column_default
        from information_schema.columns
        join missing using (table_name, column_name)
        where table_schema = desired
        order by table_name, ordinal_position asc
    loop
        return next row(
            'add column',
            jsonb_build_object(
                'schema_name', target,
                'table_name', missing_column.table_name,
                'column_name', missing_column.column_name,
                'is_nullable', missing_column.is_nullable,
                'column_default', missing_column.column_default,
                'data_type', missing_column.data_type
            )
        )::alteration;
    end loop;

    for extra_column in
        select table_name, column_name
        from information_schema.columns
        where table_schema = target
        except
        select table_name, column_name
        from information_schema.columns
        where table_schema = desired
    loop
        return next row(
            'drop column',
            jsonb_build_object(
                'schema_name', target,
                'table_name', extra_column.table_name,
                'column_name', extra_column.column_name
            )
        )::alteration;
    end loop;

    for different_column in
        with missing as (
            select table_name, column_name
            from information_schema.columns
            where table_schema = desired
            except
            select table_name, column_name
            from information_schema.columns
            where table_schema = target
        ),
        different as (
            select table_name, column_name, is_nullable, data_type, column_default
            from information_schema.columns
            where table_schema = desired
            except
            select table_name, column_name, is_nullable, data_type, column_default
            from information_schema.columns
            where table_schema = target
        )
        select table_name, column_name, is_nullable, data_type, column_default
        from different
        where not exists (
            select from missing
            where table_name = table_name
            and column_name = column_name
        )
    loop
        if different_column.column_default is not null then
            return next row(
                'alter column set default',
                jsonb_build_object(
                    'schema_name', target,
                    'table_name', different_column.table_name,
                    'column_name', different_column.column_name,
                    'column_default', different_column.column_default
                )
            )::alteration;
        else
            return next row(
                'alter column drop default',
                jsonb_build_object(
                    'schema_name', target,
                    'table_name', different_column.table_name,
                    'column_name', different_column.column_name,
                    'column_default', different_column.column_default
                )
            )::alteration;
        end if;

        if different_column.is_nullable then
            return next row(
                'alter column drop not null',
                jsonb_build_object(
                    'table', different_column.table_name,
                    'column', different_column.column_name,
                    'is_nullable', different_column.is_nullable
                )
            )::alteration;
        else
            return next row(
                'alter column set not null',
                jsonb_build_object(
                    'table', different_column.table_name,
                    'column', different_column.column_name,
                    'is_nullable', different_column.is_nullable
                )
            )::alteration;
        end if;

        return next row(
            'alter column type',
            jsonb_build_object(
                'table', different_column.table_name,
                'column', different_column.column_name,
                'type', different_column.data_type
            )
        )::alteration;
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
    alteration alteration;
begin
    for alteration in
        select * from alterations(desired, target)
        where case when keep_extra is true
            then type not in ('drop table', 'drop column')
            else true
            end
    loop
        perform exec(alteration.ddl, dry_run);
    end loop;
end;
$$;

commit;
