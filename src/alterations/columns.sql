create or replace function pgdiff.altered_columns(
    desired text,
    target text,
    cascade bool default false
) returns setof pgdiff.alteration
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with column_to_add as (
    with missing (table_name, column_name) as (
        select c.relname, a.attname -- compare only those two with "except", because "ordinal_position" can be always different
        from pg_attribute a
        join pg_class c on (c.oid = a.attrelid)
        where c.relnamespace = desired::regnamespace
        and c.relkind in ('r')
        except all
        select c.relname, a.attname
        from pg_attribute a
        join pg_class c on (c.oid = a.attrelid)
        where c.relnamespace = to_regnamespace(target)
        and c.relkind in ('r')
    )
    select 'add column', format(
        'alter table %I.%I add column %I %s %s %s %s;',
        target,
        table_name,
        column_name,
        format_type(atttypid, atttypmod),
        case is_nullable::bool
            when true then ''
            else 'not null'
        end,
        case when column_default is not null
            then format('default %s', column_default)
            else ''
        end,
        case when a.attgenerated <> ''
            then format('generated always as (%s) %s',
                pg_get_expr(adbin, adrelid, true),
                case a.attgenerated when 's' then 'stored' when 'v' then 'virtual' end
            )
            else ''
        end
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name,
        'is_nullable', is_nullable,
        'column_default', column_default,
        'data_type', case when starts_with(udt_name, '_') then format('%s[]', substr(udt_name, 2)) else udt_name end
    )
    from information_schema.columns
    join missing using (table_name, column_name)
    join pg_class c on (c.relname = table_name and c.relnamespace = desired::regnamespace)
    join pg_attribute a on (a.attrelid = c.oid and a.attname = column_name)
    left join pg_attrdef ad on (ad.adrelid = c.oid and ad.adnum = a.attnum)
    where table_schema = desired
    order by table_name, ordinal_position asc
),
table_to_drop (table_name) as (
    select tablename from pg_tables dt
    where schemaname = target
    and not exists (
        select from pg_tables
        where schemaname = desired
        and tablename = dt.tablename
    )
),
column_to_drop as (
    with extra_column (table_name, column_name) as (
        select c.relname, a.attname -- compare only those two with "except", because "ordinal_position" can be always different
        from pg_attribute a
        join pg_class c on (c.oid = a.attrelid)
        where c.relnamespace =  to_regnamespace(target)
        and c.relkind in ('r')
        and not a.attisdropped
        except all
        select c.relname, a.attname
        from pg_attribute a
        join pg_class c on (c.oid = a.attrelid)
        where c.relnamespace = desired::regnamespace
        and c.relkind in ('r')
    )
    select 'drop column', format(
        'alter table %I.%I drop column %I;',
        target,
        table_name,
        column_name
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name
    )
    from extra_column c
    where not exists (
        select from table_to_drop td
        where td.table_name = c.table_name
    )
),
column_to_alter as (
    select d.*,
        d.is_nullable != t.is_nullable as nullable_changed,
        d.column_default != t.column_default as default_changed,
        d.udt_name != t.udt_name as type_changed
    from information_schema.columns d
    join information_schema.columns t using (table_name, column_name)
    where t.table_schema = target
    and d.table_schema = desired
    and not exists (
        select from column_to_add
        where table_name = t.table_name
        and column_name = t.column_name
    )
),
column_to_set_default as (
    select 'alter column set default', format(
        'alter table %I.%I alter column %I set default %s;',
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
    select 'alter column drop default', format(
        'alter table %I.%I alter column %I drop default;',
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
-- column_to_set_expression as (
--     select 'alter column set expression', format(
--         'alter table %I.%I alter column %I set expression as (%s);',
--         target,
--         table_name,
--         column_name,
--         pg_get_expr(adbin, adrelid)
--     ), jsonb_build_object(
--         'schema_name', target,
--         'table_name', table_name,
--         'column_name', column_name,
--         'expression', pg_get_expr(adbin, adrelid)
--     )
--     from column_to_alter
--     join pg_class c on (c.relname = table_name and c.relnamespace = to_regnamespace(desired))
--     join pg_attribute a on (a.attrelid = c.oid)
--     join pg_attrdef ad on (ad.adrelid = c.oid and ad.adnum = a.attnum)
--     where attgenerated <> ''
-- ),
-- column_to_drop_expression as (
--     select 'alter column drop expression', format(
--         'alter table %I.%I alter column %I drop expression;',
--         target,
--         table_name,
--         column_name
--     ), jsonb_build_object(
--         'schema_name', target,
--         'table_name', table_name,
--         'column_name', column_name
--     )
--     from column_to_alter
--     where default_changed
--     and column_default is null
-- ),
column_to_drop_not_null as (
    select 'alter column drop not null', format(
        'alter table %I.%I alter column %I drop not null;',
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
    select 'alter column set not null', format(
        'alter table %I.%I alter column %I set not null;',
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
    select 'alter column type', format(
        'alter table %I.%I alter column %I type %s;',
        target,
        table_name,
        column_name,
        -- case when starts_with(udt_name, '_') then format('%s[]', substr(udt_name, 2)) else udt_name end
        format_type(atttypid, atttypmod)
    ), jsonb_build_object(
        'schema_name', target,
        'table_name', table_name,
        'column_name', column_name,
        'data_type', format_type(atttypid, atttypmod)
        -- case when starts_with(udt_name, '_') then format('%s[]', substr(udt_name, 2)) else udt_name end
    )
    from column_to_alter
    join pg_class c on (c.relname = table_name and c.relnamespace = to_regnamespace(desired))
    join pg_attribute a on (a.attrelid = c.oid)
    where type_changed
)
select a::alteration from (
    table column_to_add
    union all table column_to_drop
    union all table column_to_set_default
    -- union all table column_to_set_expression
    -- union all table column_to_drop_expression
    union all table column_to_drop_default
    union all table column_to_drop_not_null
    union all table column_to_set_not_null
    union all table column_to_set_type
    -- order by 1
) a
$$;
