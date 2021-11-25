\set ON_ERROR_STOP on

\i diff.sql

drop schema if exists pgdiff_test cascade;
create schema pgdiff_test;
set search_path to pgdiff_test, pgdiff;

do $$ -- it creates missing tables
begin
    drop schema if exists test_target cascade;
    create table test1 ();
    create table test2 ();
    create table test3 ();

    call migrate('pgdiff_test', 'test_target', dry_run => false);

    assert (select count(*) = 3 from pg_tables
        where schemaname = 'test_target'
        and tablename in ('test1', 'test2', 'test3')
    );
    rollback;
end;
$$;


do $$ -- it adds missing columns
declare
    stack text;
begin
    drop schema if exists test_target cascade;
    create schema test_target;
    create table test_target.test1 (id int);
    create table test1 (id int, name text not null default 'ah!');

    call migrate('pgdiff_test', 'test_target', dry_run => false);

    assert (select count(*) = 2 from information_schema.columns
        where table_schema = 'test_target'
        and table_name = 'test1'
        and column_name in ('id', 'name')
    );
    rollback;
-- exception when others then
--     get stacked diagnostics stack = pg_exception_context;
--     raise exception 'STACK TRACE: %', stack;
end;
$$;


