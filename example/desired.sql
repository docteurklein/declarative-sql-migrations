begin;

drop schema if exists test cascade;
create schema test;

set local search_path to test;

create table test1 (
    test1_id int not null primary key,
    name text unique not null check (trim(name) <> '') default 1,
    price int not null check (price > 0),
    gen int generated always as (1+1) virtual
);
create index test1_name on test1 (name);

create table test2 (
    test2_id int not null primary key,
    test1_id int not null references test1 (test1_id) deferrable
);

create view v1 as
select rank() over () a
from test1;

create view v2 as
select sum(a)
from v1;

commit;
