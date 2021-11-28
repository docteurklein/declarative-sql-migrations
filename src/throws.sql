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
        (cardinality(sqlstates) > 0 and array[sqlstate] && sqlstates)
        or 
        (message_like is not null and sqlerrm ilike message_like)
        or 
        (message_like is null and cardinality(sqlstates) = 0)
    ;
end;
$$;
