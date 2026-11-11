\echo schedule
EXPLAIN (ANALYZE, BUFFERS) SELECT m.match_id, m.start_time, a.title, b.title, s.title AS stadium,
       m.result, m.goals_from_first_team, m.goals_from_second_team
FROM matches m
JOIN teams a ON a.team_id = m.first_team_id
JOIN teams b ON b.team_id = m.second_team_id
JOIN stadiums s ON s.stadium_id = m.stadium_id
WHERE m.tournament_id = 25
ORDER BY m.start_time, m.match_id LIMIT 50;

\echo events
EXPLAIN (ANALYZE, BUFFERS) SELECT e.type, e.minute, e.description, u.full_name
FROM match_events e
JOIN players p ON p.player_id = e.player_id
JOIN users u ON u.user_id = p.user_id
WHERE e.match_id = 9121
ORDER BY e.minute, e.match_event_id;

\echo player
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FILTER (WHERE e.type = 'goal') AS goals,
       count(*) FILTER (WHERE e.type = 'yellow_card') AS yellow_cards,
       count(*) FILTER (WHERE e.type = 'red_card') AS red_cards
FROM match_events e
JOIN matches m ON m.match_id = e.match_id
WHERE e.player_id = 9620 AND m.tournament_id = 25;

\echo statistics
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM get_team_statistics(25);
