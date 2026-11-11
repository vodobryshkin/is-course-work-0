\set tid random(1, 50)
SELECT m.match_id, m.start_time, a.title, b.title, s.title AS stadium,
       m.result, m.goals_from_first_team, m.goals_from_second_team
FROM matches m
JOIN teams a ON a.team_id = m.first_team_id
JOIN teams b ON b.team_id = m.second_team_id
JOIN stadiums s ON s.stadium_id = m.stadium_id
WHERE m.tournament_id = :tid
ORDER BY m.start_time, m.match_id LIMIT 50;
