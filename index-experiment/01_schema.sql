BEGIN;
CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    full_name VARCHAR(128) NOT NULL,
    gender VARCHAR(64) NOT NULL CHECK (gender IN ('male', 
'female')),
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    about_description VARCHAR(1024),
    avatar_link VARCHAR(512)
);
CREATE TABLE authorities (
    user_id BIGINT REFERENCES users (user_id),
    authority_title VARCHAR(16) CHECK (
        authority_title IN ('user', 'player', 'coach', 'referee', 
'organizer')
    ),
    PRIMARY KEY (user_id, authority_title)
);
CREATE TABLE organizers (
    organizer_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users (user_id),
    contact_email VARCHAR(255),
    contact_phone VARCHAR(32)
);
CREATE TABLE players (
    player_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users (user_id),
    height_meters NUMERIC CHECK (height_meters > 0),
    weight_kilograms NUMERIC CHECK (weight_kilograms > 0),
    handedness VARCHAR(10) CHECK (handedness IN ('left', 'right', 
'both'))
);
CREATE TABLE coaches (
    coach_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users (user_id),
    qualification_level VARCHAR(64) NOT NULL CHECK (
        qualification_level IN (
            'Начальный уровень', 'Профессиональный уровень', 
'Высшая категория'

        )
    ),
    coach_since DATE
);
CREATE TABLE referees (
    referee_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users (user_id),
    qualification_level VARCHAR(64) NOT NULL CHECK (
        qualification_level IN (
            'Судья региональной категории',
            'Судья высшего дивизиона',
            'Судья международной категории'
        )
    ),
    referee_since DATE
);
CREATE TABLE teams (
    team_id BIGSERIAL PRIMARY KEY,
    title VARCHAR NOT NULL,
    description VARCHAR(1024),
    logo_link VARCHAR(512),
    rating SMALLINT
);
CREATE TABLE teams_players (
    team_id BIGINT REFERENCES teams (team_id),
    player_id BIGINT REFERENCES players (player_id),
    PRIMARY KEY (team_id, player_id)
);
CREATE TABLE teams_coaches (
    coach_id BIGINT REFERENCES coaches (coach_id),
    team_id BIGINT REFERENCES teams (team_id),
    PRIMARY KEY (coach_id, team_id)
);
CREATE TABLE tournaments (
    tournament_id BIGSERIAL PRIMARY KEY,
    organizer_id BIGINT NOT NULL REFERENCES organizers 
(organizer_id),
    title VARCHAR(128) NOT NULL,
    tournament_type VARCHAR(64) NOT NULL CHECK (
        tournament_type IN ('league', 'cup', 'cup_with_groups')
    ),
    description VARCHAR(1024),
    players_per_team SMALLINT NOT NULL CHECK (players_per_team > 
0),
    groups_per_tournament SMALLINT,

    start_date DATE NOT NULL,
    end_date DATE,
    number_of_teams INTEGER NOT NULL CHECK (number_of_teams >= 2),
    status VARCHAR(64) NOT NULL DEFAULT 'draft' CHECK (
        status IN ('draft', 'registration', 'in_progress', 
'finished')
    ),
    uses_pots BOOLEAN NOT NULL DEFAULT FALSE,
    schedule_confirmed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    season_start_year SMALLINT CHECK (season_start_year > 0),
    CHECK (end_date >= start_date),
    CHECK (
        (tournament_type = 'cup_with_groups'
            AND groups_per_tournament IS NOT NULL
            AND groups_per_tournament BETWEEN 1 AND 
number_of_teams)
        OR
        (tournament_type <> 'cup_with_groups'
            AND groups_per_tournament IS NULL)
    )
);
CREATE TABLE teams_tournaments (
    team_id BIGINT REFERENCES teams (team_id),
    tournament_id BIGINT REFERENCES tournaments (tournament_id),
    pot_number SMALLINT CHECK (pot_number > 0),
    PRIMARY KEY (team_id, tournament_id)
);
CREATE TABLE tournament_rosters (
    tournament_roster_id BIGSERIAL PRIMARY KEY,
    player_id BIGINT NOT NULL REFERENCES players (player_id),
    team_id BIGINT NOT NULL,
    tournament_id BIGINT NOT NULL,
    position VARCHAR(64) CHECK (
        position IN ('goalkeeper', 'defender', 'midfielder', 
'forward')
    ),
    shirt_number SMALLINT NOT NULL CHECK (shirt_number > 0),
    FOREIGN KEY (team_id, tournament_id)
        REFERENCES teams_tournaments (team_id, tournament_id),
    UNIQUE (tournament_id, player_id),
    UNIQUE (tournament_id, team_id, shirt_number)
);
CREATE TABLE groups (
    group_id BIGSERIAL PRIMARY KEY,
    tournament_id BIGINT NOT NULL REFERENCES tournaments 
(tournament_id),

    group_number SMALLINT NOT NULL CHECK (group_number > 0),
    UNIQUE (tournament_id, group_number)
);
CREATE TABLE teams_groups (
    team_id BIGINT REFERENCES teams (team_id),
    group_id BIGINT REFERENCES groups (group_id),
    PRIMARY KEY (team_id, group_id)
);
CREATE TABLE stadiums (
    stadium_id BIGSERIAL PRIMARY KEY,
    title VARCHAR(64) NOT NULL,
    address VARCHAR(255) NOT NULL,
    capacity INTEGER CHECK (capacity > 0),
    city VARCHAR(128) NOT NULL
);
CREATE TABLE stadium_slots (
    stadium_slot_id BIGSERIAL PRIMARY KEY,
    stadium_id BIGINT NOT NULL REFERENCES stadiums (stadium_id),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    CHECK (end_time > start_time)
);
CREATE TABLE matches (
    match_id BIGSERIAL PRIMARY KEY,
    tournament_id BIGINT NOT NULL REFERENCES tournaments 
(tournament_id),
    first_team_id BIGINT,
    second_team_id BIGINT,
    referee_id BIGINT REFERENCES referees (referee_id),
    stadium_id BIGINT REFERENCES stadiums (stadium_id),
    start_time TIMESTAMPTZ,
    end_time TIMESTAMPTZ,
    result VARCHAR(64) CHECK (
        result IN ('first_team_win', 'second_team_win', 'draw')
    ),
    goals_from_first_team SMALLINT CHECK (goals_from_first_team >= 
0),
    goals_from_second_team SMALLINT CHECK (goals_from_second_team 
>= 0),
    stage VARCHAR(64) NOT NULL CHECK (stage IN ('league', 'group', 
'playoff')),
    round_number SMALLINT NOT NULL CHECK (round_number > 0),
    FOREIGN KEY (first_team_id, tournament_id)
        REFERENCES teams_tournaments (team_id, tournament_id),
    FOREIGN KEY (second_team_id, tournament_id)
        REFERENCES teams_tournaments (team_id, tournament_id),

    CHECK (first_team_id <> second_team_id),
    CHECK (
        (start_time IS NULL AND end_time IS NULL)
        OR (start_time IS NOT NULL AND end_time IS NOT NULL
            AND end_time > start_time)
    ),
    CHECK (
        (result IS NULL
            AND goals_from_first_team IS NULL
            AND goals_from_second_team IS NULL)
        OR
        (result IS NOT NULL
            AND first_team_id IS NOT NULL AND second_team_id IS NOT 
NULL
            AND referee_id IS NOT NULL AND stadium_id IS NOT NULL
            AND start_time IS NOT NULL AND end_time IS NOT NULL
            AND goals_from_first_team IS NOT NULL
            AND goals_from_second_team IS NOT NULL
            AND (
                (result = 'first_team_win'
                    AND (goals_from_first_team > 
goals_from_second_team
                        OR (stage = 'playoff'
                            AND goals_from_first_team = 
goals_from_second_team)))
                OR
                (result = 'second_team_win'
                    AND (goals_from_second_team > 
goals_from_first_team
                        OR (stage = 'playoff'
                            AND goals_from_first_team = 
goals_from_second_team)))
                OR
                (result = 'draw' AND stage <> 'playoff'
                    AND goals_from_first_team = 
goals_from_second_team)
            ))
    )
);
CREATE TABLE match_events (
    match_event_id BIGSERIAL PRIMARY KEY,
    player_id BIGINT NOT NULL REFERENCES players (player_id),
    match_id BIGINT NOT NULL REFERENCES matches (match_id),
    type VARCHAR(32) NOT NULL CHECK (
        type IN ('goal', 'yellow_card', 'red_card')
    ),
    description VARCHAR(64) NOT NULL,
    minute SMALLINT CHECK (minute >= 0),
    added_minute SMALLINT CHECK (added_minute >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (added_minute IS NULL OR minute IS NOT NULL)
);
CREATE TABLE disqualifications (
    disqualification_id BIGSERIAL PRIMARY KEY,
    player_id BIGINT NOT NULL REFERENCES players (player_id),
    referee_id BIGINT NOT NULL REFERENCES referees (referee_id),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason_description TEXT,
    tournament_id BIGINT NOT NULL REFERENCES tournaments 
(tournament_id),
    created_by_user_id BIGINT NOT NULL REFERENCES users (user_id),
    FOREIGN KEY (tournament_id, player_id)
        REFERENCES tournament_rosters (tournament_id, player_id),
    CHECK (end_date >= start_date)
);
COMMIT;
