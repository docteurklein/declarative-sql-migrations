# declarative-sql-migrations

## what?

A postgres migration tool based on diffing 2 schemata.

## how?

```shell
psql -f diff.sql
psql -f desired.sql
```

```sql
set search_path to pgdiff;

drop schema if exists target cascade; -- demo

select ddl(a), * from alterations('desired', 'target') a;

-- create schema target                                                                                                            │     0 │ create schema              │ {"schema_name": "target"}
-- create table target.test1 ()                                                                                                    │     1 │ create table               │ {"table_name": "test1", "schema_name": "target"}
-- create table target.test2 ()                                                                                                    │     1 │ create table               │ {"table_name": "test2", "schema_name": "target"}
-- alter table target.test1 add column name text not null default 1                                                                │     2 │ add column                 │ {"data_type": "text", "table_name": "test1", "column_name": "name", "is_nullable": "NO", "schema_name": "target", "column_default": "1"}
-- alter table target.test1 add column price integer                                                                               │     2 │ add column                 │ {"data_type": "integer", "table_name": "test1", "column_name": "price", "is_nullable": "YES", "schema_name": "target", "column_default": null}
-- alter table target.test2 add column test1_id integer not null                                                                   │     2 │ add column                 │ {"data_type": "integer", "table_name": "test2", "column_name": "test1_id", "is_nullable": "NO", "schema_name": "target", "column_default": null}
-- alter table target.test1 add column test1_id integer not null                                                                   │     2 │ add column                 │ {"data_type": "integer", "table_name": "test1", "column_name": "test1_id", "is_nullable": "NO", "schema_name": "target", "column_default": null}
-- alter table target.test2 add column test2_id integer not null                                                                   │     2 │ add column                 │ {"data_type": "integer", "table_name": "test2", "column_name": "test2_id", "is_nullable": "NO", "schema_name": "target", "column_default": null}
-- alter table target.test1 add constraint test1_pkey PRIMARY KEY (test1_id)                                                       │     4 │ alter table add constraint │ {"ddl": "PRIMARY KEY (test1_id)", "table_name": "test1", "schema_name": "target", "constraint_name": "test1_pkey"}
-- alter table target.test2 add constraint test2_pkey PRIMARY KEY (test2_id)                                                       │     4 │ alter table add constraint │ {"ddl": "PRIMARY KEY (test2_id)", "table_name": "test2", "schema_name": "target", "constraint_name": "test2_pkey"}
-- alter table target.test1 add constraint test1_name_key UNIQUE (name)                                                            │     5 │ alter table add constraint │ {"ddl": "UNIQUE (name)", "table_name": "test1", "schema_name": "target", "constraint_name": "test1_name_key"}
-- alter table target.test1 add constraint test1_price_check CHECK ((price > 0))                                                   │     5 │ alter table add constraint │ {"ddl": "CHECK ((price > 0))", "table_name": "test1", "schema_name": "target", "constraint_name": "test1_price_check"}
-- alter table target.test2 add constraint test2_test1_id_fkey FOREIGN KEY (test1_id) REFERENCES target.test1(test1_id) DEFERRABLE │     5 │ alter table add constraint │ {"ddl": "FOREIGN KEY (test1_id) REFERENCES target.test1(test1_id) DEFERRABLE", "table_name": "test2", "schema_name": "target", "constraint_name": "test2_test1_id_fkey"}
-- CREATE INDEX test1_name ON target.test1 USING btree (name)                                                                      │     6 │ create index               │ {"ddl": "CREATE INDEX test1_name ON target.test1 USING btree (name)", "index_name": "test1_name", "table_name": "desired.test1", "schema_name": "target"}


call pgdiff.migrate('desired', 'target',
    dry_run => true,
    keep_extra => false
);
```
