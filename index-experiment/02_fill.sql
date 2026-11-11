BEGIN;

INSERT INTO users (user_id, username, full_name, gender, password_hash, email)
SELECT n, 'user_' || n, 'Пользователь ' || n, 'male', 'test_hash',
       'user_' || n || '@example.invalid'
FROM generate_series(1, 21100) AS s(n);

INSERT INTO organizers (organizer_id, user_id)
SELECT n, n FROM generate_series(1, 50) AS s(n);

INSERT INTO coaches (coach_id, user_id, qualification_level)
SELECT n, n + 50, 'Профессиональный уровень'
FROM generate_series(1, 1000) AS s(n);

INSERT INTO referees (referee_id, user_id, qualification_level)
SELECT n, n + 1050, 'Судья региональной категории'
FROM generate_series(1, 50) AS s(n);

INSERT INTO players (player_id, user_id, height_meters, weight_kilograms, handedness)
SELECT n, n + 1100, 1.70 + (n % 20) * 0.01, 65 + n % 25, 'right'
FROM generate_series(1, 20000) AS s(n);

INSERT INTO authorities SELECT user_id, 'user' FROM users;
INSERT INTO authorities SELECT user_id, 'organizer' FROM organizers;
INSERT INTO authorities SELECT user_id, 'coach' FROM coaches;
INSERT INTO authorities SELECT user_id, 'referee' FROM referees;
INSERT INTO authorities SELECT user_id, 'player' FROM players;

INSERT INTO teams (team_id, title, rating)
SELECT n, 'Команда ' || n, 100 + n % 900
FROM generate_series(1, 1000) AS s(n);

INSERT INTO teams_players (team_id, player_id)
SELECT (player_id - 1) / 20 + 1, player_id FROM players;

INSERT INTO teams_coaches (coach_id, team_id)
SELECT team_id, team_id FROM teams;

INSERT INTO tournaments (
    tournament_id, organizer_id, title, tournament_type, players_per_team,
    start_date, end_date, number_of_teams, status, season_start_year
)
SELECT n, n, 'Турнир ' || n, 'league', 11,
       DATE '2026-06-01', DATE '2026-07-31', 20, 'in_progress', 2026
FROM generate_series(1, 50) AS s(n);

INSERT INTO teams_tournaments (team_id, tournament_id)
SELECT team_id, (team_id - 1) / 20 + 1 FROM teams;

INSERT INTO tournament_rosters (
    tournament_roster_id, player_id, team_id, tournament_id, position, shirt_number
)
SELECT player_id, player_id, (player_id - 1) / 20 + 1,
       (player_id - 1) / 400 + 1,
       CASE WHEN (player_id - 1) % 20 = 0 THEN 'goalkeeper'
            WHEN (player_id - 1) % 20 < 8 THEN 'defender'
            WHEN (player_id - 1) % 20 < 15 THEN 'midfielder'
            ELSE 'forward' END,
       (player_id - 1) % 20 + 1
FROM players;

INSERT INTO stadiums (stadium_id, title, address, capacity, city)
SELECT n, 'Стадион ' || n, 'Тестовая улица, ' || n, 5000, 'Санкт-Петербург'
FROM generate_series(1, 50) AS s(n);

CREATE TEMP TABLE test_pairs ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY a.tournament_id, a.team_id, b.team_id) AS id,
       a.tournament_id, a.team_id AS first_team, b.team_id AS second_team
FROM teams_tournaments a
JOIN teams_tournaments b ON b.tournament_id = a.tournament_id
WHERE a.team_id <> b.team_id;

INSERT INTO stadium_slots (stadium_slot_id, stadium_id, start_time, end_time)
SELECT id, tournament_id,
       TIMESTAMPTZ '2026-06-01 10:00+03' + ((id - 1) % 380) * INTERVAL '3 hours',
       TIMESTAMPTZ '2026-06-01 12:00+03' + ((id - 1) % 380) * INTERVAL '3 hours'
FROM test_pairs;

INSERT INTO matches (
    match_id, tournament_id, first_team_id, second_team_id, referee_id, stadium_id,
    start_time, end_time, stage, round_number,
    result, goals_from_first_team, goals_from_second_team
)
SELECT p.id, p.tournament_id, p.first_team, p.second_team,
       p.tournament_id, p.tournament_id, s.start_time, s.end_time, 'league',
       ((p.id - 1) % 380) / 10 + 1,
       CASE WHEN (p.id - 1) % 380 < 360 THEN 'first_team_win' END,
       CASE WHEN (p.id - 1) % 380 < 360 THEN 2 END,
       CASE WHEN (p.id - 1) % 380 < 360 THEN 1 END
FROM test_pairs p JOIN stadium_slots s ON s.stadium_slot_id = p.id;

-- Три гола и одно предупреждение на завершённый матч, всего 72000 событий.
INSERT INTO match_events (player_id, match_id, type, description, minute)
SELECT CASE WHEN n = 3 THEN m.second_team_id * 20
            WHEN n = 4 THEN (m.first_team_id - 1) * 20 + 2
            ELSE m.first_team_id * 20 END,
       m.match_id, CASE WHEN n = 4 THEN 'yellow_card' ELSE 'goal' END,
       CASE WHEN n = 4 THEN 'Предупреждение' ELSE 'Гол' END, n * 20
FROM matches m CROSS JOIN generate_series(1, 4) AS s(n)
WHERE m.result IS NOT NULL;

INSERT INTO disqualifications (
    player_id, referee_id, start_date, end_date, reason_description,
    tournament_id, created_by_user_id
)
SELECT t.team_id * 20, tt.tournament_id, DATE '2026-11-01', DATE '2026-11-17',
       'Тестовая дисквалификация', tt.tournament_id, 1050 + tt.tournament_id
FROM teams t JOIN teams_tournaments tt USING (team_id);

SELECT setval(pg_get_serial_sequence('users', 'user_id'), 21100);
SELECT setval(pg_get_serial_sequence('organizers', 'organizer_id'), 50);
SELECT setval(pg_get_serial_sequence('coaches', 'coach_id'), 1000);
SELECT setval(pg_get_serial_sequence('referees', 'referee_id'), 50);
SELECT setval(pg_get_serial_sequence('players', 'player_id'), 20000);
SELECT setval(pg_get_serial_sequence('teams', 'team_id'), 1000);
SELECT setval(pg_get_serial_sequence('tournaments', 'tournament_id'), 50);
SELECT setval(pg_get_serial_sequence('tournament_rosters', 'tournament_roster_id'), 20000);
SELECT setval(pg_get_serial_sequence('stadiums', 'stadium_id'), 50);
SELECT setval(pg_get_serial_sequence('stadium_slots', 'stadium_slot_id'), 19000);
SELECT setval(pg_get_serial_sequence('matches', 'match_id'), 19000);

COMMIT;
ANALYZE;
