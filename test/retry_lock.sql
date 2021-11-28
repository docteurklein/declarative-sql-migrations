do $$
begin
    raise info $it$

    it retries if lock_not_available
    $it$;

    drop schema if exists desired cascade;
    create schema desired;
    create table desired.test1 as select 1 as i;
    commit; -- unfortunately necessary for other sessions to see it

    perform dblink_connect('conn1', 'dbname=' || current_database());

    -- session1: create a locking select for a while then rollback
    perform dblink_send_query('conn1', $sql$
        begin;
        select from desired.test1;  -- generate a concurrent lock
        select pg_sleep(greatest(1, floor(random() * 2))); -- sleep for 1 to 2 seconds
        rollback;
    $sql$);

    -- session2: attempt to alter, impossible for now because of lock
    call pgdiff.exec('alter table desired.test1 alter column i set not null',
        max_attempts => 10
    );

    -- assert col is not null
    begin
        insert into desired.test1 values (null);
    exception when others then
        return;
    end;
    raise exception 'desired.test1.i should be not null';
end;
$$;
