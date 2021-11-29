do $$
begin
    raise info $it$

    it tells if some statement throws some exception
    $it$;

    assert
        not throws('select 1'),
        'not throws';
    assert
        not throws('select 1', sqlstates => array['WHATEVER']),
        'not throws';
    assert
        throws('select 1/0'),
        'throws any, including division_by_zero';
    assert
        throws('select 1/0', sqlstates => array['22012']),
        'throws division_by_zero (22012)';
    assert
        not throws('select 1/0', sqlstates => array['NOPE']),
        'does not match NOPE sqlstate';
    assert
        not throws('select 1/0', message_like => '%division by zero%', sqlstates => array['NOPE']),
        'matches part of message but not sqlstates';
    assert
        throws('select 1/0', message_like => '%division by zero%', sqlstates => array['22012']),
        'matches part of message AND sqlstates';
    assert
        not throws('select 1/0', '%NOOOO%', sqlstates => array['NOPE']),
        'no match of message nor sqlstate';
    assert
        not throws('select 1/0', sqlstates => array['NOPE']),
        'no match of message nor sqlstate';
end;
$$;
