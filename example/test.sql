set search_path to pgdiff;

\i desired.sql

drop schema if exists target cascade;

select * from alterations('desired', 'target') a;

call pgdiff.migrate('desired', 'target',
    dry_run => false
);

alter table desired.test1 add column test text not null default 'ah' check (length(test) > 0);

select * from alterations('desired', 'target') a;

call pgdiff.migrate('desired', 'target',
    dry_run => false
);

select * from alterations('desired', 'target') a;
