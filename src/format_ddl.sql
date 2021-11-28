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
        when 'alter table add column'
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
