do $$
begin
    raise info e'\nit creates missing tables\n';

    create schema test_desired;
    create table test_desired.test1 ();
    create table test_desired.test2 ();
    create table test_desired.test3 ();

    call migrate('test_desired', 'test_target', dry_run => false);

    assert (select count(*) = 3 from pg_tables
        where schemaname = 'test_target'
    );
    rollback;
end;
$$;
