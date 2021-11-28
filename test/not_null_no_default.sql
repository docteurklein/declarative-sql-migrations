do $$
begin
    raise info $it$

    it fails to add not null columns without default value
    $it$;

    drop schema if exists desired cascade;
    drop schema if exists target cascade;
    create schema desired;
    create table desired.test1 (i int not null, j int not null);

    create schema target;
    create table target.test1 as select 1 as i;


    begin
        call migrate('desired', 'target', dry_run => false, max_attempts => 1);
    exception when others then
        return;
    end;
    raise exception 'migrate() should have thrown an exception';
end;
$$;
