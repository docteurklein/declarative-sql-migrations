do $$
begin
    raise info $it$

    it migrates
    $it$;

    assert (
        with checks as (
            select id(c) from plpgsql_check_function_tb('migrate(text,text,bool,bool,text,int,bigint,bigint,text[])') c
        )
        select 0 = count(*) from checks
    );
end;
$$;
