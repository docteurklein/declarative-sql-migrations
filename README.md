# declarative-sql-migrations

## what?

A postgres migration tool based on diffing 2 schemata.

### API

```sql
-- a type representing an alteration
type alteration as (
    "order" int, -- smaller number means higher priority
    type ddl_type,
    ddl text,
    details jsonb
);

-- execute or retries (expentional backoff with jitter) any statement that throws any of sqlstates
procedure exec(
    ddl text,
    lock_timeout text = '50ms',
    max_attempts int = 30,
    cap_ms bigint = 60000,
    base_ms bigint = 10,
    sqlstates text[] default '{}'::text[] -- see https://www.postgresql.org/docs/current/errcodes-appendix.html
);

-- returns the set of all alterations to make "target" similar to "desired"
function alterations(
    desired text, -- the reference schema
    target text -- the schema to alter,
    cascade bool default false, -- include "CASCADE" in emitted statements that support it
) returns setof alteration
strict parallel restricted;

-- prints and optionnaly executes all alterations
procedure migrate(
    desired text, -- the reference schema
    target text -- the schema to alter
    dry_run bool default true, -- only print
    keep_data bool default false, -- do not emit "DROP" statements that remove data
    cascade bool default false, -- include "CASCADE" in emitted statements that support it
    lock_timeout text = '50ms',
    max_attempts int = 30,
    cap_ms bigint = 60000,
    base_ms bigint = 10,
    sqlstates text[] default '{}'::text[]
);
```

## how?

```shell
psql -q -f example/desired.sql -f src/main.sql -c "call pgdiff.migrate('desired', 'target',
    dry_run => true
)"
```

## run tests

```shell
psql -q -f src/main.sql -f test_init.sql $(find test -name '*.sql' -printf ' -f %h/%f\n' | sort -V | xargs)
```

## example

```sql
set search_path to pgdiff;

drop schema if exists desired cascade;
create schema desired;

create table desired.test1 (
    test1_id int not null primary key,
    name text unique not null default 1,
    price int check (price > 0)
);
create index test1_name on desired.test1 (name);

create table desired.test2 (
    test2_id int not null primary key,
    test1_id int not null references desired.test1 (test1_id) deferrable
);

drop schema if exists target cascade;

select * from pgdiff.alterations('desired', 'target') a;

-- create schema target                                                                                                            │     0 │ create schema              │ {"schema_name": "target"}
-- create table target.test1 ()                                                                                                    │     1 │ create table               │ {"table_name": "test1", "schema_name": "target"}
-- create table target.test2 ()                                                                                                    │     1 │ create table               │ {"table_name": "test2", "schema_name": "target"}
-- alter table target.test1 add column name text not null default 1                                                                │     2 │ add column                 │ {"data_type": "text", "table_name": "test1", "column_name": "name", "is_nullable": "NO", "schema_name": "target", "column_default": "1"}
-- alter table target.test1 add column price integer                                                                               │     2 │ add column                 │ {"data_type": "integer", "table_name": "test1", "column_name": "price", "is_nullable": "YES", "schema_name": "target", "column_default": null}
-- alter table target.test2 add column test1_id integer not null                                                                   │     2 │ add column                 │ {"data_type": "integer", "table_name": "test2", "column_name": "test1_id", "is_nullable": "NO", "schema_name": "target", "column_default": null}
-- alter table target.test1 add column test1_id integer not null                                                                   │     2 │ add column                 │ {"data_type": "integer", "table_name": "test1", "column_name": "test1_id", "is_nullable": "NO", "schema_name": "target", "column_default": null}
-- alter table target.test2 add column test2_id integer not null                                                                   │     2 │ add column                 │ {"data_type": "integer", "table_name": "test2", "column_name": "test2_id", "is_nullable": "NO", "schema_name": "target", "column_default": null}
-- alter table target.test1 add constraint test1_pkey PRIMARY KEY (test1_id)                                                       │     4 │ alter table add constraint │ {"table_name": "test1", "schema_name": "target", "constraint_name": "test1_pkey"}
-- alter table target.test2 add constraint test2_pkey PRIMARY KEY (test2_id)                                                       │     4 │ alter table add constraint │ {"table_name": "test2", "schema_name": "target", "constraint_name": "test2_pkey"}
-- alter table target.test1 add constraint test1_name_key UNIQUE (name)                                                            │     5 │ alter table add constraint │ {"table_name": "test1", "schema_name": "target", "constraint_name": "test1_name_key"}
-- alter table target.test1 add constraint test1_price_check CHECK ((price > 0))                                                   │     5 │ alter table add constraint │ {"table_name": "test1", "schema_name": "target", "constraint_name": "test1_price_check"}
-- alter table target.test2 add constraint test2_test1_id_fkey FOREIGN KEY (test1_id) REFERENCES target.test1(test1_id) DEFERRABLE │     5 │ alter table add constraint │ {"test2", "schema_name": "target", "constraint_name": "test2_test1_id_fkey"}
-- CREATE INDEX test1_name ON target.test1 USING btree (name)                                                                      │     6 │ create index               │ {"index_name": "test1_name", "table_name": "desired.test1", "schema_name": "target"}


call pgdiff.migrate('desired', 'target',
    dry_run => false
);

alter table desired.test1 add column test text not null default 'ah' check (length(test) > 0);

select * from pgdiff.alterations('desired', 'target') a;

-- alter table target.test1 add column test text not null default 'ah'::text           │     2 │ add column                 │ {"data_type": "text", "table_name": "test1", "column_name": "test", "is_nullable": "NO", "schema_name": "target", "column_default": "'ah'::text"}
-- alter table target.test1 add constraint test1_test_check CHECK ((length(test) > 0)) │     5 │ alter table add constraint │ {"table_name": "test1", "schema_name": "target", "constraint_name": "test1_test_check"}

call pgdiff.migrate('desired', 'target',
    dry_run => false
);

select * from pgdiff.alterations('desired', 'target') a;

-- done!
```

## hacking


## live reload

```
inotifywait -e create -e close_write -m -r --format='%w%f' \
    src test* \
    | xargs -I{} psql --single-transaction -f {}
```


## validate records

```
create table test1 (
    id int not null,
    content text not null check (length(content) > 0),
    age int check (age > 18),
    work int not null,
    check ((age >= 18 and work < 2 ) or (age < 18 and work > 2))
);


select * from pgdiff.violations('{"content": "a"}'::jsonb, 'test1'::regclass::oid) v ;
   col   |        name         |                                  def                                  | status
---------+---------------------+-----------------------------------------------------------------------+---------
 content | test1_content_check | CHECK ((length(content) > 0))                                         | valid
 work    | test1_check         | CHECK ((((age >= 18) AND (work < 2)) OR ((age < 18) AND (work > 2)))) | null
 age     | test1_age_check     | CHECK ((age > 18))                                                    | invalid
 age     | test1_check         | CHECK ((((age >= 18) AND (work < 2)) OR ((age < 18) AND (work > 2)))) | invalid
 id      |                     |                                                                       | null
```
