do $$
declare
    stack text;
begin
    raise info $it$

    it executes and retries some statements
    $it$;

    call exec('select 1');
    assert (select throws($sql$
        call exec('select 1/0', max_attempts => 3)
    $sql$));

-- exception when others then
--     get stacked diagnostics stack = pg_exception_context;
--     raise exception 'STACK TRACE: %', stack;
end;
$$;
