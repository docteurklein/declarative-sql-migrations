do $$
begin
    raise info $it$

    it returns a set of violations for a record
    $it$;

    drop schema if exists desired cascade;
    create schema desired;
    set local search_path to desired, pgdiff, pgdiff_test;
    create table test1 (
	id int not null,
	content text not null check (length(content) > 0),
	age int check (age > 18),
	work int not null,
	check ((age >= 18 and work < 2 ) or (age < 18 and work > 2))
    );

    -- assert count(_log(v, null)) > 0 from pgdiff.violations('{"content": ""}'::jsonb,'desired.test1'::regclass::oid) v;
end;
$$;
