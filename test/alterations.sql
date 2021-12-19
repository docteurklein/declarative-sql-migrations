do $$
begin
    raise info $it$

    it returns a set of alterations
    $it$;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create table desired.test1 ();
    create function desired.f1 () returns int language sql immutable parallel safe as 'select 1';

    assert count(_log(a, null)) = 0 from
        (select * from alterations('desired', 'target')
        except values(
            0, 'create schema'::ddl_type,
            'create schema target',
            jsonb_build_object(
                'schema_name', 'target'
            )
        ),
        (
            1, 'create table'::ddl_type,
            'create table target.test1 ()',
            jsonb_build_object(
                'schema_name', 'target',
                'table_name', 'test1'
            )
        ),
        (
            8, 'create routine'::ddl_type,
            $ddl$CREATE OR REPLACE FUNCTION target.f1()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$select 1$function$
$ddl$,
            jsonb_build_object(
                'schema_name', 'target',
                'routine_name', 'f1'
            )
        )) a
    ;
end;
$$;
