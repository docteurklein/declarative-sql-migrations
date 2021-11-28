do $$
declare
    stack text;
begin
    raise info e'\nit retries if lock_not_available\n';

    drop schema if exists test_desired cascade;
    create schema test_desired;
    create table test_desired.test1 as select 1 as i;
    commit;

    perform dblink_connect('conn1', 'dbname=' || current_database());

    -- session1: create a locking select
    perform dblink_exec('conn1', 'begin');
    perform dblink_send_query('conn1', 'select * from test_desired.test1');

    begin
        -- session2: attempt to alter, impossible because of lock
        call exec('alter table test_desired.test1 alter column i set not null',
            max_attempts => 3
        );
    exception when others then
        -- session1: release lock
        perform dblink_exec('conn1', 'rollback');
    end;

    -- session1: attempt to alter
    call exec('alter table test_desired.test1 alter column i set not null',
        max_attempts => 3
    );
    begin
        insert into test_desired.test1 values (null);
    exception when others then
        return;
    end;
    raise exception 'test_desired.test1.i should be not null';
end;
$$;
