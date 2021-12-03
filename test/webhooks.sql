\i src/webhook.sql

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

    insert into desired.test1 values (1);

    assert 1 = count(*) from pg_logical_slot_peek_changes('test_slot', null, null);

    perform pg_logical_emit_message(true, 'wal2json', 'this message will be delivered');

    call webhook('test_slot', 'http://httpbin.org/post', polls => 3);

    assert 0 = count(*) from pg_logical_slot_peek_changes('test_slot', null, null);
end;
$$;
