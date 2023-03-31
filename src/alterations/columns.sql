create or replace function pgdiff.altered_columns(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with column_to_add as (
    with missing as (
        select table_name, column_name -- compare only those two with "except", because "ordinal_position" can be always different
        from information_schema.columns
        where table_schema = desired
        except
        select table_name, column_name
        from information_schema.columns
        where table_schema = target
    )
    select 2, 'add column', format(
        'alter table %I.%I add column %I %s %s %s',
        target,
        table_name,
        column_name,
        data_type,
        case is_nullable::bool
            when true then ''
            else 'not null'
        end,
        case when column_default is not null
            then format('default %s', column_default)
            else ''
        end
    ), jsonb_build_object(
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
table_to_drop as (
    select from pg_tables dt
    where schemaname = target
    and not exists (
        select from pg_tables
        where schemaname = desired
        and tablename = dt.tablename
    )
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
    select 6, 'drop column', format(
        'alter table %I.%I drop column %I',
        target,
        table_name,
        column_name
    ), jsonb_build_object(
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
column_to_set_default as (
    select 3, 'alter column set default', format(
        'alter table %I.%I alter column %I set default %s',
        target,
        table_name,
        column_name,
        column_default
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name,
        'column_default', column_default
    )
    from column_to_alter
    where default_changed
    and column_default is not null
),
column_to_drop_default as (
    select 3, 'alter column drop default', format(
        'alter table %I.%I alter column %I drop default',
        target,
        table_name,
        column_name
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name,
        'column_default', column_default
    )
    from column_to_alter
    where default_changed
    and column_default is null
),
column_to_drop_not_null as (
    select 3, 'alter column drop not null', format(
        'alter table %I.%I alter column %I drop not null',
        target,
        table_name,
        column_name
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name,
        'is_nullable', is_nullable::bool
    )
    from column_to_alter
    where nullable_changed
    and is_nullable::bool
),
column_to_set_not_null as (
    select 3, 'alter column set not null', format(
        'alter table %I.%I alter column %I set not null',
        target,
        table_name,
        column_name
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name,
        'is_nullable', is_nullable::bool
    )
    from column_to_alter
    where nullable_changed
    and not is_nullable::bool
),
column_to_set_type as (
    select 3, 'alter column type', format(
        'alter table %I.%I alter column %I type %s',
        target,
        table_name,
        column_name,
        data_type
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name,
        'data_type', data_type
    )
    from column_to_alter
    where type_changed
)
select a::alteration from (
    table column_to_add
    union all table column_to_drop
    union all table column_to_set_default
    union all table column_to_drop_default
    union all table column_to_drop_not_null
    union all table column_to_set_not_null
    union all table column_to_set_type
    order by 1, 2
) a
$$;
