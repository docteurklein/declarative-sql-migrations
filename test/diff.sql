do $$ -- it creates missing tables
begin
    create table test1 ();
    create table test2 ();
    create table test3 ();

    call migrate('pgdiff_test', 'test_target', dry_run => false);

    assert (select count(*) = 3 from pg_tables
        where schemaname = 'test_target'
    );
    rollback;
end;
$$;
