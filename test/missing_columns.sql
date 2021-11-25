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
