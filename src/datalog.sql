-- <program> ::= <fact> <program> | <rule> <program> | ɛ
-- <fact> ::=  <relation> "(" <constant-list> ")." 
-- <rule> ::= <atom> ":-" <atom-list> "."
-- <atom> ::= <relation> "(" <term-list> ")"
-- <atom-list> ::= <atom> | <atom> "," <atom-list>
-- <term> ::= <constant> | <variable>
-- <term-list> ::= <term> | <term> "," <term-list>
-- <constant-list> ::= <constant> | <constant> "," <constant-list>

begin;
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
commit;

begin;

create table individual(
    name text primary key,
    born int not null
);
insert into individual values
    ('xerces', 200),
    ('brooke', 230),
    ('damocles', 270),
    ('flo', 1986)
;
create table parent(
    parent text not null references individual(name),
    child text not null references individual(name),
    primary key (parent, child)
);
insert into parent values
    ('xerces', 'brooke'),
    ('brooke', 'damocles'),
    ('damocles', 'flo')
;

create or replace recursive view ancestor (ancestor, descendant, age_diff) as
    select parent, child, c.born - p.born
    from parent
    join individual p on p.name = parent.parent
    join individual c on c.name = parent.child
    union select parent, descendant, d.born - a.born
    from ancestor
    join parent on child = ancestor
    join individual a on a.name = ancestor
    join individual d on d.name = descendant
;

assert not exists(
    select * from datalog($dl$
        ancestor(a, b age_diff) :-
            parent(a, b),
            individual(a, _, a_born), -- positional or named: individual(name: a, born: a_born)
            individual(b, _, b_born),
            age_diff = a_born - b_born.
        ancestor(a, b, age_diff) :-
            parent(a, c),
            ancestor(c, b),
            individual(a, _, a_born),
            individual(b, _, b_born),
            age_diff = a_born - b_born.
    $dl$) _(ancestor, descendant)
    except table ancestor
);

assert not exists(select * from datalog($json$
    {
        "rules": [
            {
                "relation": "ancestor",
                "terms": [
                    {"variable": "a"},
                    {"variable": "b"},
                    {"variable": "age_diff"}
                ],
                "body": [
                    {
                        "relation": "parent",
                        "terms": [
                            {"variable": "a"},
                            {"variable": "b"}
                        ]
                    },
                    {
                        "relation": "individual",
                        "terms": [
                            {"variable": "a"},
                            "underscore",
                            {"variable": "a_born"}
                        ]
                    },
                    {
                        "relation": "individual",
                        "terms": [
                            {"variable": "b"},
                            "underscore",
                            {"variable": "b_born"}
                        ]
                    },
                    {
                        "expression": "age_diff",
                        "terms": [
                            {"variable": "a_born"},
                            {"operator": "-"},
                            {"variable": "b_born"}
                        ]
                    }
                ]
            },
            {
                "relation": "ancestor",
                "terms": [
                    {"variable": "a"},
                    {"variable": "b"},
                    {"variable": "age_diff"}
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
                    },
                    {
                        "relation": "individual",
                        "terms": [
                            {"variable": "a"},
                            "underscore",
                            {"variable": "a_born"}
                        ]
                    },
                    {
                        "relation": "individual",
                        "terms": [
                            {"variable": "b"},
                            "underscore",
                            {"variable": "b_born"}
                        ]
                    },
                    {
                        "expression": "age_diff",
                        "terms": [
                            {"variable": "a_born"},
                            {"operator": "-"},
                            {"variable": "b_born"}
                        ]
                    }
                ]
            }
        ]
    }
    $json$::jsonb) _(ancestor, descendant, age_diff)
    except table ancestor
);
rollback;
