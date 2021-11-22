# declarative-sql-migrations

## what?

A postgres migration tool based on diffing 2 schemata.

## how?

psql -f diff.sql
psql -f desired.sql

```
select * from pgdiff.alterations('desired', 'target');
                   ddl                    │    type     │               details
──────────────────────────────────────────┼─────────────┼──────────────────────────────────────
 alter table test2.test1 drop column name │ drop column │ {"table": "test1", "column": "name"}

call pgdiff.migrate('desired', 'target',
    dry_run => true,
    keep_extra => false
);
```
