begin;

drop schema if exists pgdiff cascade;
create schema pgdiff;

\set search_path to pgdiff;

create function pgdiff.ddl(inout ddl text, dry_run bool default true) returns text
language plpgsql as $$
begin
    raise notice '%', ddl;
    if not dry_run then
        execute ddl;
    end if;
end
$$;

drop type if exists pgdiff.ddl_type cascade;
create type pgdiff.ddl_type as enum (
    'add table',
    'add column',
    'alter column',
    'drop table',
    'drop column'
);

drop type if exists pgdiff.alteration cascade;
create type pgdiff.alteration as (
    ddl text,
    type pgdiff.ddl_type,
    details jsonb
);

create function pgdiff.alterations(desired text, target text) returns setof pgdiff.alteration
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
    for missing_table in
        select table_name from information_schema.tables
        where (table_schema, table_type) = (desired, 'BASE TABLE')
        except
        select table_name from information_schema.tables
        where (table_schema, table_type) = (target, 'BASE TABLE')
    loop
        return next row(
            format('create table %I.%I ()', target, missing_table.table_name),
            'add_table',
            jsonb_build_object(
                'table', missing_table.table_name
            )
        )::pgdiff.alteration;
    end loop;

    for extra_table in
        select table_name from information_schema.tables
        where (table_schema, table_type) = (target, 'BASE TABLE')
        except
        select table_name from information_schema.tables
        where (table_schema, table_type) = (desired, 'BASE TABLE')
    loop
        return next row(
            format('drop table %I.%I', target, extra_table.table_name),
            'drop table',
            jsonb_build_object(
                'table', extra_table.table_name
            )
        )::pgdiff.alteration;
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
            format(
                'alter table %I.%I add column %I %s %s %s',
                target,
                missing_column.table_name,
                missing_column.column_name,
                missing_column.data_type,
                case missing_column.is_nullable::bool
                    when true then ''
                    else 'not null'
                end,
                case when missing_column.column_default is not null
                    then format('default %s', missing_column.column_default)
                    else ''
                end
            ),
            'add_column',
            jsonb_build_object(
                'table', missing_column.table_name,
                'column', missing_column.column_name,
                'is_nullable', missing_column.is_nullable,
                'default', missing_column.column_default
            )
        )::pgdiff.alteration;
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
            format(
                'alter table %I.%I drop column %I',
                target,
                extra_column.table_name,
                extra_column.column_name
            ),
            'drop column',
            jsonb_build_object(
                'table', extra_column.table_name,
                'column', extra_column.column_name
            )
        )::pgdiff.alteration;
    end loop;

    for different_column in
        select table_name, column_name, is_nullable, data_type, column_default
        from information_schema.columns
        where table_schema = desired
        except
        select table_name, column_name, is_nullable, data_type, column_default
        from information_schema.columns
        where table_schema = target
    loop
        if different_column.column_default is not null then
            return next row(
                format(
                    'alter table %I.%I alter column %I set default %s',
                    target,
                    different_column.table_name,
                    different_column.column_name,
                    different_column.column_default
                ),
                'alter_column',
                jsonb_build_object(
                    'table', different_column.table_name,
                    'column', different_column.column_name,
                    'default', different_column.column_default
                )
            )::pgdiff.alteration;
        else
            return next row(
                format(
                    'alter table %I.%I alter column %I drop default',
                    target,
                    different_column.table_name,
                    different_column.column_name
                ),
                'alter_column',
                jsonb_build_object(
                    'table', different_column.table_name,
                    'column', different_column.column_name,
                    'default', different_column.column_default
                )
            )::pgdiff.alteration;
        end if;

        if different_column.is_nullable then
            return next row(
                format(
                    'alter table %I.%I alter column %I drop not null',
                    target,
                    different_column.table_name,
                    different_column.column_name
                ),
                'alter_column',
                jsonb_build_object(
                    'table', different_column.table_name,
                    'column', different_column.column_name,
                    'is_nullable', different_column.is_nullable
                )
            )::pgdiff.alteration;
        else
            return next row(
                format(
                    'alter table %I.%I alter column %I set not null',
                    target,
                    different_column.table_name,
                    different_column.column_name
                ),
                'alter_column',
                jsonb_build_object(
                    'table', different_column.table_name,
                    'column', different_column.column_name,
                    'is_nullable', different_column.is_nullable
                )
            )::pgdiff.alteration;
        end if;

        return next row(
            format(
                'alter table %I.%I alter column %I type %s',
                target,
                different_column.table_name,
                different_column.column_name,
                different_column.data_type
            ),
            'alter_column',
            jsonb_build_object(
                'table', different_column.table_name,
                'column', different_column.column_name,
                'type', different_column.data_type
            )
        )::pgdiff.alteration;
    end loop;
end;
$$;

create procedure pgdiff.migrate(
    desired text,
    target text,
    dry_run bool default true,
    keep_extra bool default false
)
language plpgsql as $$
declare
    alteration pgdiff.alteration;
begin
    for alteration in
        select * from pgdiff.alterations(desired, target)
        where case when keep_extra is true
            then type not in ('drop table', 'drop column')
            else true
            end
    loop
        perform pgdiff.ddl(alteration.ddl, dry_run);
    end loop;
end;
$$;

commit;
