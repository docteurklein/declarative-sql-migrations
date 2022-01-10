do $$
declare
    stack text;
begin
    raise info $it$

    it adds missing columns
    $it$;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create schema target;
    create table target.test1 (id int);
    create index test1_id_idx on target.test1 (id);
    create table desired.test1 (id int, name text not null default 'ah!');

    call migrate('desired', 'target', dry_run => false);

    assert (
        select count(*) = 1
        from pg_index di
        join pg_class dc
        on di.indexrelid = dc.oid
        and dc.relnamespace = 'target'::regnamespace
        and dc.relname = 'test1_id_idx'

    );
    rollback;
-- exception when others then
--     get stacked diagnostics stack = pg_exception_context;
--     raise exception 'STACK TRACE: %', stack;
end;
$$;
