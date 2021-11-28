do $$
declare
    stack text;
begin
    raise info e'\nit adds missing columns\n';

    create schema test_desired;
    create schema test_target;
    create table test_desired.test1 (id int);
    create table test_target.test1 (id int, name text);

    call migrate('test_desired', 'test_target', dry_run => false);

    assert (select count(*) = 1 from information_schema.columns
        where table_schema = 'test_target'
    );
    rollback;
-- exception when others then
--     get stacked diagnostics stack = pg_exception_context;
--     raise exception 'STACK TRACE: %', stack;
end;
$$;
