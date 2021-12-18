do $$
declare
    stack text;
    r record;
begin
    raise info $it$

    it traverses graphs
    $it$;

    drop schema if exists graph cascade;
    create schema graph;
    set local search_path to graph, pgdiff;

    create table director (director_name text primary key);
    create table film (film_name text primary key, director_name text not null references director (director_name));
    create table actor (actor_name text primary key);
    create table film_actor (
        film_name text not null references film (film_name),
        actor_name text not null references actor (actor_name)
    );

    insert into director select 'director#'||i from generate_series(1, 4) i;
    insert into film
        select 'film#'||i, (select * from director order by random() limit 1)
        from generate_series(1, 10) i;
    insert into actor select 'actor#'||i from generate_series(1, 100) i;

    insert into film_actor select film_name, actor_name from
    (select * from film order by random() limit 5) film,
    (select * from actor order by random() limit 50) actor;

    with all_couples as (
        select * from film, actor
    )
    insert into film_actor select film_name, actor_name
    from all_couples
    order by random()
    limit 50;

    insert into film_actor values ('film#1', 'actor#1')
    on conflict do nothing;

    -- MATCH
    --    (actor:Person)-[:ACTED_IN]-(film:Movie),
    --    (director:Person)-[:DIRECTED]-(film:Movie) 
    -- WHERE actor.name='Tom Hanks'
    -- RETURN actor.name, film.title, director.name ;

    select film_name, director_name
    from film
    join director using (director_name)
    left join film_actor using (film_name)
    left join actor using (actor_name)
    where actor_name = 'actor#1'

    into r;
    raise notice '%', r;

    create or replace function edge(
        from record,
        label text,
        to record
    ) returns table (_ record)
    language plpgsql strict parallel restricted
    set search_path to pgdiff
    as $s$
    begin
        return query select v::text;
    end;
    $s$;

    select *
    from director d
    join film f using (director_name)
    join actor b on edge(b, 'played_in', f)
    where actor_name = 'actor#1'

    into r;
    raise notice '%', r;


-- exception when others then
--     get stacked diagnostics stack = pg_exception_context;
--     raise exception 'STACK TRACE: %', stack;
end;
$$;
