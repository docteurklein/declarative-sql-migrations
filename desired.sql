drop schema if exists desired cascade;
create schema desired;

set search_path to desired;

create table test1 (
    test1_id int not null primary key
);

create table test2 (
    test2_id int not null primary key,
    name text not null,
    test1_id int not null references test1 (test1_id)
);
