create function timing(statement text) returns interval
language plpgsql as $$
declare start timestamp;
begin
    start := clock_timestamp();
    execute statement;
    return clock_timestamp() - start;
end;
$$;
