\i src/webhook.sql

create extension if not exists http;

do $$
begin
    raise info $it$

    it emits http requests on logical slot changes
    $it$;

    perform pg_drop_replication_slot(slot_name) from pg_replication_slots
    where slot_name = 'test_slot';
    perform pg_create_logical_replication_slot('test_slot', 'wal2json');

    drop schema if exists desired cascade;
    create schema desired;
    create table desired.test1 (id int primary key);
    commit;

    perform pg_logical_emit_message(true, 'wal2json', 'this message will be delivered');

    assert 1 = count(*) from pg_logical_slot_peek_changes('test_slot', null, null);

    call webhook(
        'test_slot',
        'http://httpbin.org/post',
        -- 'http://0:8080/post',
        polls => 3,
        tables_like => array['desired.%']
    );

    assert 0 = count(*) from pg_logical_slot_peek_changes('test_slot', null, null);
end;
$$;
