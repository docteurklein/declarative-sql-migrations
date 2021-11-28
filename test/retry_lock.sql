do $$
declare
    stack text;
    _ record;
begin
    raise info e'\nit retries if lock_not_available\n';

    drop schema if exists test_desired cascade;
    create schema test_desired;
    create table test_desired.test1 as select 1 as i;
    commit;

    perform dblink_connect('conn1', 'dbname=' || current_database());

    -- session1: create a locking select for a while then rollback
    perform dblink_send_query('conn1', $sql$
        begin;
        select from test_desired.test1;  -- generate a concurrent lock
        select pg_sleep(greatest(0.8, floor(random() * 2))); -- sleep for 0.8 to 2 seconds
        rollback;
    $sql$);

    -- session2: attempt to alter, impossible for now because of lock
    call pgdiff.exec('alter table test_desired.test1 alter column i set not null',
        max_attempts => 10
    );

    -- assert col is not null
    begin
        insert into test_desired.test1 values (null);
    exception when others then
        return;
    end;
    raise exception 'test_desired.test1.i should be not null';
end;
$$;
