CREATE INDEX idx_matches_tournament_time
    ON matches (tournament_id, start_time, match_id);

CREATE INDEX idx_events_match_time
    ON match_events (match_id, minute, match_event_id);

CREATE INDEX idx_events_player_match
    ON match_events (player_id, match_id);
