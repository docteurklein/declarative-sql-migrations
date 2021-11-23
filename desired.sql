begin;

drop schema if exists desired cascade;
create schema desired;

set local search_path to desired;

create table test1 (
    test1_id int not null primary key,
    name text unique not null default 1,
    price int check (price > 0)
);
create index test1_name on test1 (name);

create table test2 (
    test2_id int not null primary key,
    test1_id int not null references test1 (test1_id) deferrable
);

commit;
