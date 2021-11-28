do $$
begin
    raise info $it$

    it creates missing tables
    $it$;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create table desired.test1 ();
    create table desired.test2 ();
    create table desired.test3 ();

    call migrate('desired', 'target', dry_run => false);

    assert (select count(*) = 3 from pg_tables
        where schemaname = 'target'
    );
    rollback;
end;
$$;
