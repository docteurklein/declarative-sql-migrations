# declarative-sql-migrations

## what?

A postgres migration tool based on diffing 2 schemata.

## how?

    psql -f diff.sql -c \
    "call pgdiff.migrate('desired', 'target',
        dry_run => true,
        keep_extra => false
    )"

