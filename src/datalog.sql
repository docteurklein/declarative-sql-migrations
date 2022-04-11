-- <program> ::= <fact> <program> | <rule> <program> | ɛ
-- <fact> ::=  <relation> "(" <constant-list> ")." 
-- <rule> ::= <atom> ":-" <atom-list> "."
-- <atom> ::= <relation> "(" <term-list> ")"
-- <atom-list> ::= <atom> | <atom> "," <atom-list>
-- <term> ::= <constant> | <variable>
-- <term-list> ::= <term> | <term> "," <term-list>
-- <constant-list> ::= <constant> | <constant> "," <constant-list>

create or replace function pgdiff.datalog(
    dl text
) returns setof record
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with recursive parser(input, output) as (
    select null, regexp_matches(dl, $ARE$
    ?x # extended ARE syntax
    ^(\w) # rule name
        \((.*)\) # constant-list
    )\.
    $ARE$, 'g')
    union all
    select
        case input[0]
            when ''
    from parser where rest is null
)
select * from parser;
$$;

create or replace function pgdiff.datalog(
    dl jsonb
) returns setof record
language sql strict stable
set search_path to pgdiff, pg_catalog
as $$
with 
select 1
$$;

assert exists(select from datalog($dl$
    ancestor(a, b) :- parent(a, b).
    ancestor(a, b) :- parent(a, c), ancestor(c, b).
$dl$));

assert exists(select from datalog($json$
{
    "rules": [
        {
            "relation": "ancestor",
            "terms": [
                {"variable": "a"},
                {"variable": "b"}
            ],
            "body": [
                {
                    "relation": "parent",
                    "terms": [
                        {"variable": "a"},
                        {"variable": "b"}
                    ]
                }
            ]
        },
        {
            "relation": "ancestor",
            "terms": [
                {"variable": "a"},
                {"variable": "b"}
            ],
            "body": [
                {
                    "relation": "parent",
                    "terms": [
                        {"variable": "a"},
                        {"variable": "c"}
                    ]
                },
                {
                    "relation": "ancestor",
                    "terms": [
                        {"variable": "c"},
                        {"variable": "b"}
                    ]
                }
            ]
        }
    ]
}
$json$::jsonb));

