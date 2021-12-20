do $$
begin
    raise info $it$

    it self-replicates
    $it$;

    drop schema if exists "pgdiff-self" cascade;

    call migrate('pgdiff', 'pgdiff-self', dry_run => false);

    assert count(*) = 0 from alterations('pgdiff', 'pgdiff-self');

    call "pgdiff-self".migrate('pgdiff', 'pgdiff-self', dry_run => true);
end;
$$;
