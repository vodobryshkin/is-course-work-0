\set mid random(1, 19000)
SELECT e.type, e.minute, e.description, u.full_name
FROM match_events e
JOIN players p ON p.player_id = e.player_id
JOIN users u ON u.user_id = p.user_id
WHERE e.match_id = :mid
ORDER BY e.minute, e.match_event_id;
