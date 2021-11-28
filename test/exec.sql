do $$
begin
    raise info $it$

    it executes and retries some statements
    $it$;

    assert not throws($sql$
        call exec('select 1')
    $sql$);

    assert throws($sql$
        call exec('select 1/0', max_attempts => 2)
    $sql$);

    assert timing($sql$
        do $do$
        begin
            call exec('select 1/0', max_attempts => 10);
        exception when others then return; end;
        $do$;
    $sql$) > interval '2 seconds', 'runs for long';
end;
$$;
