do $$
begin
    raise info $it$

    it executes and retries some statements
    $it$;

    assert (
        with checks as (
            select _log(c, null) from plpgsql_check_function_tb('exec(text,text,int,bigint,bigint,text[])') c
        )
        select 0 = count(*) from checks
    );

    assert not throws($sql$
        call exec('select 1')
    $sql$);

    assert throws($sql$
        call exec('select 1/0', max_attempts => 2)
    $sql$);

    assert timing($sql$
        do $do$
        begin
            assert throws($sql2$
                call exec('select 1/0', max_attempts => 10);
            $sql2$, message_like => 'division by zero');
        end;
        $do$;
    $sql$) > interval '2 seconds', 'runs for long';
end;
$$;
