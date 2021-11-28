do $$
declare
    stack text;
begin
    raise info $it$

    it removes extra columns
    $it$;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create schema target;
    create table desired.test1 (id int);
    create table target.test1 (id int, name text);

    call migrate('desired', 'target', dry_run => false);

    assert (select count(*) = 1 from information_schema.columns
        where table_schema = 'target'
    );
    rollback;
-- exception when others then
--     get stacked diagnostics stack = pg_exception_context;
--     raise exception 'STACK TRACE: %', stack;
end;
$$;
