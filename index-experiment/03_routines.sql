BEGIN;
CREATE PROCEDURE finish_match(
    p_match_id BIGINT,
    p_first_goals INTEGER,
    p_second_goals INTEGER,
    p_winner_team_id BIGINT DEFAULT NULL
)

LANGUAGE plpgsql
AS $$
DECLARE
    v_match matches%ROWTYPE;
    v_result VARCHAR(64);
    v_winner BIGINT;
BEGIN
    IF p_first_goals IS NULL OR p_second_goals IS NULL
       OR p_first_goals NOT BETWEEN 0 AND 32767
       OR p_second_goals NOT BETWEEN 0 AND 32767 THEN
        RAISE EXCEPTION 'Некорректный счёт';
    END IF;
    SELECT * INTO v_match
    FROM matches WHERE match_id = p_match_id FOR UPDATE;
    IF NOT FOUND OR v_match.result IS NOT NULL THEN
        RAISE EXCEPTION 'Матч не найден или результат уже 
сохранён';
    END IF;
    IF v_match.first_team_id IS NULL OR v_match.second_team_id IS 
NULL THEN
        RAISE EXCEPTION 'Оба участника матча должны быть 
определены';
    END IF;
    IF p_first_goals > p_second_goals THEN
        v_result := 'first_team_win';
        v_winner := v_match.first_team_id;
    ELSIF p_second_goals > p_first_goals THEN
        v_result := 'second_team_win';
        v_winner := v_match.second_team_id;
    ELSIF v_match.stage = 'playoff' THEN
        IF p_winner_team_id = v_match.first_team_id THEN
            v_result := 'first_team_win';
        ELSIF p_winner_team_id = v_match.second_team_id THEN
            v_result := 'second_team_win';
        ELSE
            RAISE EXCEPTION 'При ничейном счёте плей-офф укажите 
победителя';
        END IF;
        v_winner := p_winner_team_id;
    ELSE
        v_result := 'draw';
    END IF;
    IF p_winner_team_id IS NOT NULL
       AND p_winner_team_id IS DISTINCT FROM v_winner THEN
        RAISE EXCEPTION 'Указанный победитель противоречит 
результату';

    END IF;
    UPDATE matches
    SET goals_from_first_team = p_first_goals,
        goals_from_second_team = p_second_goals,
        result = v_result
    WHERE match_id = p_match_id;
END;
$$;

CREATE FUNCTION get_team_statistics(p_tournament_id BIGINT)
RETURNS TABLE (
    team_id BIGINT, title VARCHAR, played BIGINT,
    wins BIGINT, draws BIGINT, losses BIGINT,
    goals_for BIGINT, goals_against BIGINT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH results AS (
        SELECT m.first_team_id AS participant_id,
               m.goals_from_first_team AS scored,
               m.goals_from_second_team AS conceded,
               CASE m.result
                   WHEN 'first_team_win' THEN 'win'
                   WHEN 'second_team_win' THEN 'loss'
                   ELSE 'draw'
               END AS outcome
        FROM matches AS m
        WHERE m.tournament_id = p_tournament_id AND m.result IS NOT 
NULL
        UNION ALL
        SELECT m.second_team_id,
               m.goals_from_second_team, m.goals_from_first_team,
               CASE m.result
                   WHEN 'second_team_win' THEN 'win'
                   WHEN 'first_team_win' THEN 'loss'
                   ELSE 'draw'
               END
        FROM matches AS m
        WHERE m.tournament_id = p_tournament_id AND m.result IS NOT 

NULL
    )
    SELECT t.team_id, t.title,
           COUNT(r.participant_id),
           COUNT(*) FILTER (WHERE r.outcome = 'win'),
           COUNT(*) FILTER (WHERE r.outcome = 'draw'),
           COUNT(*) FILTER (WHERE r.outcome = 'loss'),
           COALESCE(SUM(r.scored), 0), COALESCE(SUM(r.conceded), 0)
    FROM teams_tournaments AS tt
    JOIN teams AS t ON t.team_id = tt.team_id
    LEFT JOIN results AS r ON r.participant_id = t.team_id
    WHERE tt.tournament_id = p_tournament_id
    GROUP BY t.team_id, t.title;
END;
$$;

CREATE FUNCTION check_match_teams()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_type VARCHAR(64);
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.result IS NOT NULL THEN
            RAISE EXCEPTION 'Нельзя удалить завершённый матч';
        END IF;
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.result IS NOT NULL AND NEW IS DISTINCT FROM OLD THEN
            RAISE EXCEPTION 'Нельзя изменять завершённый матч';
        END IF;
        IF (NEW.tournament_id, NEW.first_team_id, 
NEW.second_team_id)
           IS DISTINCT FROM
           (OLD.tournament_id, OLD.first_team_id, 
OLD.second_team_id)
           AND EXISTS (
               SELECT 1 FROM match_events WHERE match_id = 
OLD.match_id
           ) THEN

            RAISE EXCEPTION 'У матча уже есть события: участники 
зафиксированы';
        END IF;
    END IF;
    SELECT tournament_type INTO v_type
    FROM tournaments WHERE tournament_id = NEW.tournament_id
    FOR NO KEY UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Турнир не найден';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(ARRAY[
            NEW.first_team_id, NEW.second_team_id
        ]) AS participant(team_id)
        WHERE participant.team_id IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM teams_tournaments AS tt
              WHERE tt.team_id = participant.team_id
                AND tt.tournament_id = NEW.tournament_id
          )
    ) THEN
        RAISE EXCEPTION 'Указанные команды должны участвовать в 
турнире';
    END IF;
    IF NOT (
        (v_type = 'league' AND NEW.stage = 'league')
        OR (v_type = 'cup' AND NEW.stage = 'playoff')
        OR (v_type = 'cup_with_groups' AND NEW.stage IN ('group', 
'playoff'))
    ) THEN
        RAISE EXCEPTION 'Этап матча не соответствует формату 
турнира';
    END IF;
    IF NEW.stage = 'group'
       AND NEW.first_team_id IS NOT NULL AND NEW.second_team_id IS 
NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM teams_groups AS a
           JOIN teams_groups AS b ON b.group_id = a.group_id
           JOIN groups AS g ON g.group_id = a.group_id
           WHERE a.team_id = NEW.first_team_id AND b.team_id = 
NEW.second_team_id
             AND g.tournament_id = NEW.tournament_id
       ) THEN
        RAISE EXCEPTION 'Участники группового матча должны быть в 
одной группе';

    END IF;
    -- Общие ресурсы блокируются и проверяются между всеми турнирами.
    PERFORM 1 FROM teams
    WHERE team_id IN (NEW.first_team_id, NEW.second_team_id)
    ORDER BY team_id FOR NO KEY UPDATE;
    PERFORM 1 FROM stadiums WHERE stadium_id = NEW.stadium_id
    FOR NO KEY UPDATE;
    PERFORM 1 FROM referees WHERE referee_id = NEW.referee_id
    FOR NO KEY UPDATE;
    IF NEW.start_time IS NOT NULL AND NEW.end_time IS NOT NULL THEN
        IF NEW.stadium_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM stadium_slots AS s
            WHERE s.stadium_id = NEW.stadium_id
              AND s.start_time <= NEW.start_time
              AND s.end_time >= NEW.end_time
        ) THEN
            RAISE EXCEPTION 'Стадион недоступен в выбранное время';
        END IF;
        IF EXISTS (
            SELECT 1 FROM matches AS m
            WHERE m.match_id IS DISTINCT FROM NEW.match_id
              AND m.start_time < NEW.end_time
              AND m.end_time > NEW.start_time
              AND (
                  m.stadium_id = NEW.stadium_id
                  OR m.referee_id = NEW.referee_id
                  OR NEW.first_team_id IN (m.first_team_id, 
m.second_team_id)
                  OR NEW.second_team_id IN (m.first_team_id, 
m.second_team_id)
              )
        ) THEN
            RAISE EXCEPTION 'Конфликт времени команды, стадиона или 
судьи';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION check_stadium_slots()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_stadium_ids BIGINT[] := ARRAY[]::BIGINT[];
BEGIN
    IF TG_OP <> 'INSERT' THEN
        v_stadium_ids := array_append(v_stadium_ids, 
OLD.stadium_id);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        v_stadium_ids := array_append(v_stadium_ids, 
NEW.stadium_id);
    END IF;
    PERFORM 1 FROM stadiums
    WHERE stadium_id = ANY(v_stadium_ids)
    ORDER BY stadium_id FOR NO KEY UPDATE;
    IF EXISTS (
        SELECT 1 FROM matches AS m
        WHERE m.stadium_id = ANY(v_stadium_ids)
          AND m.start_time IS NOT NULL AND m.end_time IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM stadium_slots AS s
              WHERE s.stadium_id = m.stadium_id
                AND s.start_time <= m.start_time AND s.end_time >= 
m.end_time
          )
    ) THEN
        RAISE EXCEPTION 'Изменение доступности нарушает 
расписание';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION check_event_player()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_match matches%ROWTYPE;
BEGIN
    SELECT * INTO v_match FROM matches
    WHERE match_id = NEW.match_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Матч не найден';
    END IF;
    IF v_match.first_team_id IS NULL OR v_match.second_team_id IS 
NULL THEN
        RAISE EXCEPTION 'Участники матча ещё не определены';
    END IF;
    IF NEW.player_id IS NOT NULL THEN
        PERFORM 1 FROM tournament_rosters AS tr
        WHERE tr.tournament_id = v_match.tournament_id
          AND tr.team_id IN (v_match.first_team_id, 
v_match.second_team_id)
          AND tr.player_id = NEW.player_id
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Футболист отсутствует в ростерах 
команд матча';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION validate_tournament_personnel(p_tournament_id 
BIGINT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_tournament tournaments%ROWTYPE;
    v_user_id BIGINT;
BEGIN
    SELECT * INTO v_tournament FROM tournaments
    WHERE tournament_id = p_tournament_id FOR NO KEY UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    SELECT personnel.user_id INTO v_user_id
    FROM (
        SELECT tr.team_id, p.user_id
        FROM tournament_rosters AS tr
        JOIN players AS p ON p.player_id = tr.player_id
        WHERE tr.tournament_id = p_tournament_id
        UNION ALL
        SELECT tc.team_id, c.user_id
        FROM teams_coaches AS tc
        JOIN coaches AS c ON c.coach_id = tc.coach_id
        JOIN teams_tournaments AS tt ON tt.team_id = tc.team_id
        WHERE tt.tournament_id = p_tournament_id
    ) AS personnel
    GROUP BY personnel.user_id
    HAVING COUNT(DISTINCT personnel.team_id) > 1
    LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'Пользователь % представляет разные команды 
турнира %',
            v_user_id, p_tournament_id;
    END IF;
    SELECT r.user_id INTO v_user_id
    FROM matches AS m
    JOIN referees AS r ON r.referee_id = m.referee_id
    WHERE m.tournament_id = p_tournament_id
      AND (
          EXISTS (
              SELECT 1 FROM tournament_rosters AS tr
              JOIN players AS p ON p.player_id = tr.player_id
              WHERE tr.tournament_id = p_tournament_id
                AND p.user_id = r.user_id
          )

          OR EXISTS (
              SELECT 1 FROM teams_tournaments AS tt
              JOIN teams_coaches AS tc ON tc.team_id = tt.team_id
              JOIN coaches AS c ON c.coach_id = tc.coach_id
              WHERE tt.tournament_id = p_tournament_id
                AND c.user_id = r.user_id
          )
      )
    LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'Пользователь % не может судить турнир % 
своей команды',
            v_user_id, p_tournament_id;
    END IF;
    -- Ростер нельзя менять так, чтобы уже записанные события стали неверными.
    IF EXISTS (
        SELECT 1 FROM match_events AS e
        JOIN matches AS m ON m.match_id = e.match_id
        WHERE m.tournament_id = p_tournament_id
          AND NOT EXISTS (
              SELECT 1 FROM tournament_rosters AS tr
              WHERE tr.tournament_id = p_tournament_id
                AND tr.player_id = e.player_id
                AND tr.team_id IN (m.first_team_id, 
m.second_team_id)
          )
    ) THEN
        RAISE EXCEPTION 'Изменение ростера нарушает историю 
событий';
    END IF;
    IF (SELECT COUNT(*) FROM teams_tournaments
        WHERE tournament_id = p_tournament_id) > 
v_tournament.number_of_teams THEN
        RAISE EXCEPTION 'Превышено количество участников турнира';
    END IF;
    IF NOT v_tournament.uses_pots AND EXISTS (
        SELECT 1 FROM teams_tournaments
        WHERE tournament_id = p_tournament_id AND pot_number IS NOT 
NULL
    ) THEN
        RAISE EXCEPTION 'В этом турнире корзины не используются';
    END IF;
    IF EXISTS (
        SELECT 1 FROM groups AS g

        WHERE g.tournament_id = p_tournament_id
          AND (v_tournament.tournament_type <> 'cup_with_groups'
               OR g.group_number > 
v_tournament.groups_per_tournament)
    ) THEN
        RAISE EXCEPTION 'Группа не соответствует параметрам 
турнира';
    END IF;
    IF EXISTS (
        SELECT 1 FROM teams_groups AS tg
        JOIN groups AS g ON g.group_id = tg.group_id
        WHERE g.tournament_id = p_tournament_id
          AND NOT EXISTS (
              SELECT 1 FROM teams_tournaments AS tt
              WHERE tt.tournament_id = p_tournament_id AND 
tt.team_id = tg.team_id
          )
    ) OR EXISTS (
        SELECT tg.team_id FROM teams_groups AS tg
        JOIN groups AS g ON g.group_id = tg.group_id
        WHERE g.tournament_id = p_tournament_id
        GROUP BY tg.team_id HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'Команда должна участвовать в турнире и 
только в одной его группе';
    END IF;
    IF EXISTS (
        SELECT 1 FROM matches AS m
        WHERE m.tournament_id = p_tournament_id AND m.stage = 
'group'
          AND m.first_team_id IS NOT NULL AND m.second_team_id IS 
NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM teams_groups AS a
              JOIN teams_groups AS b ON b.group_id = a.group_id
              JOIN groups AS g ON g.group_id = a.group_id
              WHERE a.team_id = m.first_team_id AND b.team_id = 
m.second_team_id
                AND g.tournament_id = p_tournament_id
          )
    ) THEN
        RAISE EXCEPTION 'Изменение групп нарушает участников 
группового матча';
    END IF;
    IF EXISTS (
        SELECT 1 FROM matches AS m
        WHERE m.tournament_id = p_tournament_id

          AND NOT (
              (v_tournament.tournament_type = 'league' AND m.stage 
= 'league')
              OR (v_tournament.tournament_type = 'cup' AND m.stage 
= 'playoff')
              OR (v_tournament.tournament_type = 'cup_with_groups'
                  AND m.stage IN ('group', 'playoff'))
          )
    ) THEN
        RAISE EXCEPTION 'Формат турнира противоречит этапам его 
матчей';
    END IF;
END;
$$;

CREATE FUNCTION check_tournament_personnel()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_old_id BIGINT;
    v_new_id BIGINT;
    v_tournament_id BIGINT;
BEGIN
    IF TG_TABLE_NAME IN (
        'tournaments', 'teams_tournaments', 'tournament_rosters', 
'groups', 'matches'
    ) THEN
        IF TG_OP <> 'INSERT' THEN
            v_ids := array_append(v_ids, OLD.tournament_id);
        END IF;
        IF TG_OP <> 'DELETE' THEN
            v_ids := array_append(v_ids, NEW.tournament_id);
        END IF;
    ELSIF TG_TABLE_NAME = 'teams_groups' THEN
        IF TG_OP <> 'INSERT' THEN v_old_id := OLD.group_id; END IF;
        IF TG_OP <> 'DELETE' THEN v_new_id := NEW.group_id; END IF;
        SELECT array_agg(DISTINCT tournament_id) INTO v_ids FROM 
groups

        WHERE group_id IN (v_old_id, v_new_id);
    ELSIF TG_TABLE_NAME = 'teams_coaches' THEN
        IF TG_OP <> 'INSERT' THEN v_old_id := OLD.team_id; END IF;
        IF TG_OP <> 'DELETE' THEN v_new_id := NEW.team_id; END IF;
        SELECT array_agg(DISTINCT tournament_id) INTO v_ids FROM 
teams_tournaments
        WHERE team_id IN (v_old_id, v_new_id);
    ELSIF TG_TABLE_NAME = 'players' THEN
        SELECT array_agg(DISTINCT tournament_id) INTO v_ids
        FROM tournament_rosters WHERE player_id = NEW.player_id;
    ELSIF TG_TABLE_NAME = 'coaches' THEN
        SELECT array_agg(DISTINCT tt.tournament_id) INTO v_ids
        FROM teams_tournaments AS tt
        JOIN teams_coaches AS tc ON tc.team_id = tt.team_id
        WHERE tc.coach_id = NEW.coach_id;
    ELSIF TG_TABLE_NAME = 'referees' THEN
        SELECT array_agg(DISTINCT tournament_id) INTO v_ids FROM 
matches
        WHERE referee_id = NEW.referee_id;
    END IF;
    FOR v_tournament_id IN
        SELECT DISTINCT x FROM unnest(v_ids) AS t(x)
        WHERE x IS NOT NULL ORDER BY x
    LOOP
        PERFORM validate_tournament_personnel(v_tournament_id);
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER check_match_teams
BEFORE INSERT OR UPDATE OR DELETE ON matches
FOR EACH ROW EXECUTE FUNCTION check_match_teams();

CREATE TRIGGER check_stadium_slots
AFTER INSERT OR UPDATE OR DELETE ON stadium_slots
FOR EACH ROW EXECUTE FUNCTION check_stadium_slots();

CREATE TRIGGER check_event_player
BEFORE INSERT OR UPDATE OF player_id, match_id ON match_events
FOR EACH ROW EXECUTE FUNCTION check_event_player();

CREATE TRIGGER check_team_player_tournament
AFTER INSERT OR UPDATE OR DELETE ON tournament_rosters
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_team_coach_tournament

AFTER INSERT OR UPDATE OR DELETE ON teams_coaches
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_team_tournament_personnel
AFTER INSERT OR UPDATE OR DELETE ON teams_tournaments
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_match_referee_tournament
AFTER INSERT OR UPDATE OF tournament_id, referee_id ON matches
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_player_user_tournament
AFTER UPDATE OF user_id ON players
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_coach_user_tournament
AFTER UPDATE OF user_id ON coaches
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_referee_user_tournament
AFTER UPDATE OF user_id ON referees
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_group_tournament
AFTER INSERT OR UPDATE OR DELETE ON groups
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_group_teams
AFTER INSERT OR UPDATE OR DELETE ON teams_groups
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();

CREATE TRIGGER check_tournament_parameters
AFTER INSERT OR UPDATE ON tournaments
FOR EACH ROW EXECUTE FUNCTION check_tournament_personnel();
COMMIT;
