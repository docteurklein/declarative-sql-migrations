begin;

drop schema if exists desired cascade;
create schema desired;

set local search_path to desired;

create table test1 (
    test1_id int not null primary key,
    name text null default 1
);

create table test2 (
    test2_id int not null primary key,
    test1_id int not null references test1 (test1_id)
);

commit;
