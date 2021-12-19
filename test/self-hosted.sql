do $$
begin
    raise info $it$

    it self-replicates
    $it$;

    drop schema if exists "pgdiff_self" cascade;

    call migrate('pgdiff', 'pgdiff_self', dry_run => false);
    commit;

    assert count(*) = 0 from alterations('pgdiff', 'pgdiff_self');
end;
$$;
