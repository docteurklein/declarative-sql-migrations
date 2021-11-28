do $$
begin
    raise info $it$

    it retries if lock_not_available
    $it$;

    drop extension if exists dblink;
    create extension dblink;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create schema target;
    create table target.test1 as select 1 as i; -- i int null
    create table target.test2 as select 1 as i; -- i int null
    commit; --necessary for other sessions to see

    perform dblink_connect('conn1', 'dbname=' || current_database());
    perform dblink_connect('conn2', 'dbname=' || current_database());

    -- session1: create a locking select on test1 for a while then rollback
    perform dblink_send_query('conn1', $sql$
        begin;
        select from target.test1;
        select pg_sleep(greatest(5, floor(random() * 8)));
        rollback;
    $sql$);

    -- session2: create a locking select on test2 for a while then rollback
    perform dblink_send_query('conn2', $sql$
        begin;
        select from target.test2;
        select pg_sleep(greatest(2, floor(random() * 3)));
        rollback;
    $sql$);

    -- session3: attempt to alter, impossible for now because of lock
    create table desired.test1 (i int not null);
    create table desired.test2 (i int not null);
    call migrate('desired', 'target',
        max_attempts => 20,
        dry_run => false
    );

    -- assert col is not null
    assert throws('insert into target.test1 values (null)', sqlstates => array['23502']),
        'test1.i should be not null';

    assert throws('insert into target.test2 values (null)', sqlstates => array['23502']),
        'test2.i should be not null';
end;
$$;
