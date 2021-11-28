do $$
declare
    stack text;
begin
    raise info $it$

    it adds missing columns
    $it$;

    drop schema if exists desired cascade;
    create schema desired;
    create schema target;
    create table target.test1 (id int);
    create table desired.test1 (id int, name text not null default 'ah!');

    call migrate('desired', 'target', dry_run => false);

    assert (select count(*) = 2 from information_schema.columns
        where table_schema = 'target'
        and table_name = 'test1'
        and column_name in ('id', 'name')
    );
    rollback;
-- exception when others then
--     get stacked diagnostics stack = pg_exception_context;
--     raise exception 'STACK TRACE: %', stack;
end;
$$;
