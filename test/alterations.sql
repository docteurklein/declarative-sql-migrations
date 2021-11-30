do $$
begin
    raise info $it$

    it returns a set of alterations
    $it$;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create table desired.test1 ();

    assert (
        with expected as (
            values
            (
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
            )
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

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create schema target;
    create table target.test1 ();

    assert (
        with expected as (
            values
            (
                7, 'drop table'::ddl_type,
                'drop table target.test1 cascade',
                jsonb_build_object(
                    'table_name', 'test1',
                    'schema_name', 'target',
                    'cascade', true
                )
            )
        ),
        actual as (
            select * from alterations('desired', 'target', cascade => true)
        ),
        diff as (
            select id(a) from (table actual except table expected) a
        )
        select count(*) = 0
        from diff
    );
end;
$$;
