-- Special Stages boards: one best lap per player and board (board = "<layout version>/<track>").
-- The region columns come from the player's connection when they post (Cloudflare's request.cf),
-- so narrower boards (continent, country, zip code) are just filters on the same table.
CREATE TABLE IF NOT EXISTS times (
  board     TEXT    NOT NULL,
  player    TEXT    NOT NULL,
  time      REAL    NOT NULL,
  continent TEXT    NOT NULL DEFAULT '',
  country   TEXT    NOT NULL DEFAULT '',
  zip       TEXT    NOT NULL DEFAULT '',
  at        INTEGER NOT NULL,
  PRIMARY KEY (board, player)
);
CREATE INDEX IF NOT EXISTS times_world   ON times (board, time);
CREATE INDEX IF NOT EXISTS times_cont    ON times (board, continent, time);
CREATE INDEX IF NOT EXISTS times_country ON times (board, country, time);
CREATE INDEX IF NOT EXISTS times_zip     ON times (board, country, zip, time);
