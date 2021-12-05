set local search_path to pgdiff;

create or replace function alterations(
    desired text,
    target text,
    cascade bool default false
) returns setof alteration
language plpgsql strict stable
set search_path to pgdiff
as $$
declare
    alteration alteration;
begin
    for alteration in
        with schema_to_create as (
            select 0, 'create schema'::ddl_type, format('create schema %I', target), jsonb_build_object(
                'schema_name', target
            ) from pg_namespace
            where not exists (
                select from pg_namespace where nspname = target
            )
        ),
        table_to_create as (
            select 1, 'create table'::ddl_type, format('create table %I.%I ()', target, tablename), jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = desired
            except
            select 1, 'create table'::ddl_type, format('create table %I.%I ()', target, tablename), jsonb_build_object(
                'schema_name', target,
                'table_name', tablename
            ) from pg_tables
            where schemaname = target
        ),
        table_to_drop as (
            select 7, 'drop table'::ddl_type, 
            format('drop table %I.%I%s', target, tablename, 
                case cascade when true then ' cascade' else '' end
            ), jsonb_build_object(
                'schema_name', target,
                'table_name', tablename,
                'cascade', cascade
            ) from pg_tables
            where schemaname = target
            except
            select 7, 'drop table'::ddl_type, 
            format('drop table %I.%I%s', target, tablename, 
                case cascade when true then ' cascade' else '' end
            ), jsonb_build_object(
                'schema_name', target,
                'table_name', tablename,
                'cascade', cascade
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
            select 2, 'alter table add column'::ddl_type, format(
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
            select 6, 'drop column'::ddl_type, format(
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
            select 3, 'alter column set default'::ddl_type, format(
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
            select 3, 'alter column drop default'::ddl_type, format(
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
            select 3, 'alter column drop not null'::ddl_type, format(
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
            select 3, 'alter column set not null'::ddl_type, format(
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
            select 3, 'alter column type'::ddl_type, format(
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
                'alter table add constraint'::ddl_type,
                format('alter table %I.%I add constraint %s %s',
                    target,
                    relname,
                    conname,
                    replace(pg_get_constraintdef(oid), desired || '.', target || '.') -- bad
                ),
                jsonb_build_object(
                    'schema_name', target,
                    'constraint_name', conname,
                    'table_name', relname
                )
            from missing
        ),
        constraint_to_alter as (
            with different as (
                select dcl.relname, dc.conname, dc.condeferrable as _deferrable, dc.condeferred as deferred
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
            select 5, 'alter table alter constraint'::ddl_type, format(
                'alter table %I.%I alter constraint %s %s %s',
                target,
                relname,
                conname,
                case _deferrable::bool
                    when true then 'deferrable'
                    else 'not deferrable'
                end,
                case when deferred::bool
                    then 'initially deferred'
                    else 'initially immediate'
                end
            ), jsonb_build_object(
                'schema_name', target,
                'constraint_name', conname,
                'table_name', relname,
                'deferrable', _deferrable,
                'deferred', deferred
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
            select 4, 'alter table drop constraint'::ddl_type, format('alter table %I.%I drop constraint %s',
                target,
                relname,
                conname
            ), jsonb_build_object(
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
            select 6, 'create index'::ddl_type,
            replace(pg_get_indexdef(indexrelid), desired || '.', target || '.'), -- bad
            jsonb_build_object(
                'schema_name', target,
                'index_name', relname,
                'table_name', indrelid
            )
            from missing
        ),
        index_to_drop as (
            with extra as (
                select tc.relname, dt.relname as table_name
                from pg_index ti
                join pg_class tc on ti.indexrelid = tc.oid and tc.relnamespace = to_regnamespace(target)::oid
                left join pg_class dc on dc.relname = tc.relname and dc.relnamespace = desired::regnamespace::oid
                left join pg_class dt on dt.oid = ti.indrelid
                where dc.oid is null
                and not ti.indisprimary
                and not ti.indisunique
            )
            select 6, 'drop index'::ddl_type, format(
                'drop index %I.%I',
                target,
                relname
            ), jsonb_build_object(
                'schema_name', target,
                'index_name', relname,
                'table_name', table_name
            )
            from extra
        )
        table schema_to_create union
        table table_to_create union
        table table_to_drop union
        table column_to_add union
        table column_to_drop union
        table column_to_set_default union
        table column_to_drop_default union
        table column_to_drop_not_null union
        table column_to_set_not_null union
        table column_to_set_type union
        table constraint_to_create union
        table constraint_to_alter union
        table constraint_to_drop union
        table index_to_create union
        table index_to_drop
        order by 1
    loop
        return next alteration::alteration;
    end loop;
end;
$$;
