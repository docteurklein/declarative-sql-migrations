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

    assert count(_log(a)) = 0 from
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
            2, 'create routine'::ddl_type,
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

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create schema target;
    create table target.test1 (id int);
    create index idx on target.test1 (id);
    create function target.f1 () returns int language sql immutable parallel safe as 'select 1';

    assert count(_log(a)) = 0
        from (
        select * from alterations('desired', 'target', cascade => true)
        except values(
            6, 'drop index'::ddl_type,
            'drop index target.idx',
            jsonb_build_object(
                'schema_name', 'target',
                'index_name', 'idx',
                'table_name', 'test1'
            )
        ),
        (
            7, 'drop table'::ddl_type,
            'drop table target.test1 cascade',
            jsonb_build_object(
                'table_name', 'test1',
                'schema_name', 'target',
                'cascade', true
            )
        ),
        (
            7, 'drop routine'::ddl_type,
            'drop routine target.f1 () cascade',
            jsonb_build_object(
                'schema_name', 'target',
                'routine_name', 'f1'
            )
        )) a
    ;
end;
$$;
