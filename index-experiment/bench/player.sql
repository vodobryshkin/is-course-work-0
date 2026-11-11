\set tid random(1, 50)
\set player_id (:tid - 1) * 400 + random(1, 400)
SELECT count(*) FILTER (WHERE e.type = 'goal') AS goals,
       count(*) FILTER (WHERE e.type = 'yellow_card') AS yellow_cards,
       count(*) FILTER (WHERE e.type = 'red_card') AS red_cards
FROM match_events e
JOIN matches m ON m.match_id = e.match_id
WHERE e.player_id = :player_id AND m.tournament_id = :tid;
