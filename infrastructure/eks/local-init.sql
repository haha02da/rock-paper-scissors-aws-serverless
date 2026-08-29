CREATE TABLE IF NOT EXISTS games (
  session_id TEXT NOT NULL,
  game_key TEXT NOT NULL,
  id UUID NOT NULL UNIQUE,
  player_choice TEXT NOT NULL CHECK (player_choice IN ('rock', 'paper', 'scissors')),
  computer_choice TEXT NOT NULL CHECK (computer_choice IN ('rock', 'paper', 'scissors')),
  result TEXT NOT NULL CHECK (result IN ('win', 'draw', 'loss')),
  created_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (session_id, game_key)
);
CREATE INDEX IF NOT EXISTS games_created_at_idx ON games (created_at DESC);
