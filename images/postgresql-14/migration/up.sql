-- -----------------------------------------------------------------------------
-- SCHEMA
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS example;
COMMENT ON SCHEMA example IS
'Schema used for this example.';


--  ----------------------------------------------------------------------------
--  EXTENSIONS
--  ----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- -----------------------------------------------------------------------------
-- FUNCTIONS
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION example.generate_random_date(
  p_days int = 183
) RETURNS timestamptz LANGUAGE plpgsql STABLE PARALLEL RESTRICTED STRICT AS $$
DECLARE p_interval varchar;
BEGIN
  RETURN NOW() - MAKE_INTERVAL(days => (p_days * RANDOM())::int);
END;
$$;

-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION example.generate_random_between(
  p_low int,
  p_high int
) RETURNS int  LANGUAGE plpgsql STABLE PARALLEL RESTRICTED STRICT AS $$
BEGIN
   RETURN FLOOR(RANDOM()* (p_high - p_low + 1) + p_low);
END;
$$;


-- -----------------------------------------------------------------------------
-- TABLES
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS example.opinion_type (
  opinion_type_id smallint NOT NULL,
  opinion_type_display varchar(128) NOT NULL,
  opinion_type_description varchar(2048) NOT NULL DEFAULT '',
  CONSTRAINT idx_example_opinion_type_pk
    PRIMARY KEY (opinion_type_id),
  CONSTRAINT idx_example_opinion_type_display
    UNIQUE(opinion_type_display)
);
COMMENT ON TABLE example.opinion_type IS
'A user can provide their opinion towards content.';

INSERT INTO example.opinion_type (
  opinion_type_id,
  opinion_type_display,
  opinion_type_description
) VALUES
(1, 'Horrible', 'I wish I had never seen this content. I would recommend others stay away from it.'),
(2, 'Ok', 'I saw the content but would not recommend or watch it again.'),
(3, 'Good', 'I enjoyed and will probably only view the content one time. I would recommend it to others.'),
(4, 'Awesome', 'I would watch this content again and recommend it to others.'),
(5, 'Epic', 'I would consume this content anytime I was presented with it. I would evangalize it with others.');

-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS example.user_opinion (
  user_id int NOT NULL,
  content_id int NOT NULL,
  opinion_type_id smallint NOT NULL
    REFERENCES example.opinion_type(opinion_type_id),
  added_on timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT idx_example_user_opinion_user_post_pk
    PRIMARY KEY (user_id, content_id),
  CONSTRAINT idx_example_user_opinion_post_user
    UNIQUE (content_id, user_id)
);
COMMENT ON TABLE example.user_opinion IS
'A user can provide their opinion towards content.';

-- Some of our queries rely on the date the opinion was added so we will
-- index on that.
-- DROP INDEX example.idx_example_user_opinion_added_user;
CREATE INDEX IF NOT EXISTS idx_example_user_opinion_added_user
  ON example.user_opinion (added_on, user_id, opinion_type_id);

-- NOTE: About 20 seconds
DO $$ BEGIN
  -- Users who are not so active
  FOR counter IN 1..400000 LOOP
    INSERT INTO example.user_opinion(
      user_id,
      content_id,
      opinion_type_id,
      added_on
    )
    SELECT 
      example.generate_random_between(20,1000),
      example.generate_random_between(1,20000),
      example.generate_random_between(1,5),
      example.generate_random_date(183)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- users who are more active
  FOR counter IN 1..100000 LOOP
    INSERT INTO example.user_opinion(
      user_id,
      content_id,
      opinion_type_id,
      added_on
    )
    SELECT 
      example.generate_random_between(1,20),
      example.generate_random_between(1,20000),
      example.generate_random_between(1,5),
      example.generate_random_date(183)
    ON CONFLICT DO NOTHING;
  END LOOP;

END $$;

-- -----------------------------------------------------------------------------
-- VIEWS
-- -----------------------------------------------------------------------------

-- Running this materialized view takes about 87 ms
CREATE MATERIALIZED VIEW IF NOT EXISTS example.opinion_activity AS
SELECT
  uo.user_id,
  uo.opinion_type_id,
  st.opinion_type_display,
  COUNT(uo.opinion_type_id) AS opinion_count
FROM example.user_opinion AS uo
INNER JOIN example.opinion_type AS st ON st.opinion_type_id = uo.opinion_type_id
-- filter for only those users who had opinions in the last 50 days
WHERE uo.added_on >= NOW() - INTERVAL '50 days'
GROUP BY uo.user_id, uo.opinion_type_id, st.opinion_type_display
-- ordering by the opinion_count will give us the most active users
ORDER BY opinion_count DESC
-- Limit to the top 100 users
LIMIT 100;
COMMENT ON MATERIALIZED VIEW example.opinion_activity IS
'Get the 100 most active users within the past 50 days.';

-- Querying the materialized view takes about 3ms
-- SELECT *
-- FROM example.opinion_activity;

-- Setup a cron job to refresh the activity every 5 minutes.
SELECT cron.schedule('opinion_activity', '*/5 * * * *',
  $CRON$ REFRESH MATERIALIZED VIEW example.opinion_activity; $CRON$
);
