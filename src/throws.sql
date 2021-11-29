create function throws(
    statement text,
    message_like text default null,
    sqlstates text[] default '{}'::text[]
) returns bool
language plpgsql as $$
begin
    execute statement;
    return false;
exception when others then
    raise debug e'"%" throws exception "%: %"', statement, sqlstate, sqlerrm;
    return
        (
            (cardinality(sqlstates) = 0 or array[sqlstate] && sqlstates)
            and
            (message_like is null or sqlerrm ilike message_like)
        )
    ;
end;
$$;
