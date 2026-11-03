begin;

drop schema if exists test cascade;
create schema test;

set local search_path to test;

create type ty1 as (id int);
create type en1 as enum ('ok', 'notok');

create domain d1 as varchar(16) check (trim(value) <> '  ');

create table test1 (
    test1_id int not null primary key,
    en en1,
    name text unique not null,--, check (trim(name) <> '') default 1,
    price int not null,-- check (price > 0),
    gen int generated always as (1+2 ) virtual
);
create index test1_name on test1 (name);

create table test2 (
    test2_id int not null primary key,
    test1_id int not null references test1 (test1_id) deferrable initially deferred
);

create view v1 as
select 0::bigint a, 'b', 3 c  -- rank() over () a
from test1;

create view v2 as
select sum(a)
from v1;

create view alone as
select 1;

create view v3 as
select sum(1)
from v2;

create view v4 as
select sum(1)
from v2;

create view v5 as
select sum(1)
from v3;

create function test2(a int) returns int
begin atomic select 1; end;


create policy "recent" on test1
as restrictive
for all to anon
using (gen > 4)
with check (true);

commit;
