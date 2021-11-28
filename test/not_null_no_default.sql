do $$
declare
    stack text;
    t record;
begin
    raise info e'\nit fails to add not null columns without default values';

    create schema test_desired;
    create table test_desired.test1 (i int not null, j int not null);

    create schema test_target;
    create table test_target.test1 as select 1 as i;


    begin
        call migrate('test_desired', 'test_target', dry_run => false);
    exception when others then
        return;
    end;
    raise exception 'migrate() should have thrown an exception';
end;
$$;
