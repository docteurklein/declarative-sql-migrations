do $$
begin
    raise info $it$

    it returns a set of alterations
    $it$;

    drop schema if exists desired cascade;
    create schema desired;
    create table desired.test1 ();

    assert (
        with expected as (
            values
            (0 ,  'create schema'::ddl_type , jsonb_build_object(
                'schema_name', 'target'
            )),
            (1 ,  'create table'::ddl_type  , jsonb_build_object(
                'schema_name', 'target',
                'table_name', 'test1'
            ))
        ),
        actual as (
            select * from alterations('desired', 'target')
        ),
        diff as (
            table expected except table actual
        )
        select count(*) = 0
        from diff
    );
end;
$$;
