do $$
begin
    raise info $it$

    it diffs routine return type
    $it$;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create schema target;
    create function target.f1 () returns int language sql immutable parallel safe as 'select 1';
    create function desired.f1 () returns bool language sql parallel safe as 'select false';

    assert count(_log(expected, 'expected')) = 0 and count(_log(actual, 'actual')) = 0
        from alterations('desired', 'target') actual
        full outer join (values(
            7, 'drop routine'::ddl_type,
            'drop routine if exists target.f1 ()',
            jsonb_build_object(
                'schema_name', 'target',
                'routine_name', 'f1'
            )
        ),
        (
            8, 'create routine'::ddl_type,
            $ddl$CREATE OR REPLACE FUNCTION target.f1()
 RETURNS boolean
 LANGUAGE sql
 PARALLEL SAFE
AS $function$select false$function$
$ddl$,
            jsonb_build_object(
                'schema_name', 'target',
                'routine_name', 'f1'
            )
        )) expected ("order", type, ddl, details)
        on row(actual) = row(expected)
        where actual.ddl is null
        or expected.ddl is null
    ;
end;
$$;
