CREATE TABLE participants (
    id       SERIAL PRIMARY KEY,
    code     TEXT NOT NULL CHECK (code   ~ '[0-9]{4}'),
    birthday DATE NOT NULL,
    gender   TEXT     NULL CHECK (gender ~ '(M|F|O)')
);

INSERT INTO participants (code, birthday, gender)
SELECT
    TO_CHAR((RANDOM() * (9999 - 1)) + 1, '0000'),
    NOW() - ((RANDOM() * (96 - 45) + 45)::text || ' years')::interval,
    CASE
        WHEN FLOOR((RANDOM() * (16 - 1)) + 1)::integer % 15 = 0 THEN 'O'
        WHEN FLOOR((RANDOM() * ( 8 - 1)) + 1)::integer %  7 = 0 THEN NULL
        WHEN FLOOR((RANDOM() * ( 3 - 1)) + 1)::integer %  2 = 0 THEN 'F'
        ELSE 'M'
    END
FROM generate_series(1, 250);

CREATE EXTENSION multicorn;

CREATE SERVER pgosquery_srv
FOREIGN DATA WRAPPER multicorn
OPTIONS (wrapper 'pgosquery.PgOSQuery');

CREATE FOREIGN TABLE processes (
    pid         INTEGER,
    name        TEXT,
    cpu_percent FLOAT
)
SERVER pgosquery_srv
OPTIONS (
    tabletype 'processes'
);

CREATE TABLE monitored_processes (pattern TEXT UNIQUE NOT NULL);

CREATE TABLE stats (
    id             SERIAL    PRIMARY KEY,
    process_family TEXT      NOT NULL,
    cpu_percent    FLOAT     NOT NULL,
    timestamp      TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO monitored_processes (pattern)
VALUES ('chrome'), ('safari'), ('firefox'), ('postgres'), ('ruby');

CREATE VIEW stats_json AS
WITH
    columns AS (
        SELECT ARRAY_AGG(pattern ORDER BY pattern) AS list
        FROM monitored_processes
    ),
    data AS (
        SELECT ARRAY_AGG(datapoint) AS points
        FROM (
            WITH timestamps AS (
                SELECT monitored_processes.pattern, timestamps.timestamp
                FROM
                    monitored_processes,
                    (
                        SELECT DISTINCT
                            DATE_TRUNC('second', timestamp) AS timestamp
                        FROM stats
                        WHERE timestamp >= (NOW() - '1 minute'::interval)
                    ) AS timestamps
            )
            SELECT
                TO_JSON(
                    timestamps.timestamp::text ||
                    ARRAY_AGG(data.point ORDER BY timestamps.pattern)::text[]
                ) AS datapoint
            FROM
                timestamps LEFT JOIN
                (
                    SELECT
                        AVG(cpu_percent)                      AS point,
                        DATE_TRUNC('second', stats.timestamp) AS timestamp,
                        monitored_processes.pattern           AS family
                    FROM
                        stats INNER JOIN
                        monitored_processes ON
                        stats.process_family = monitored_processes.pattern
                    WHERE timestamp >= (NOW() - '1 minute'::interval)
                    GROUP BY 2, 3
                ) AS data ON (
                    timestamps.pattern   = data.family    AND
                    timestamps.timestamp = data.timestamp
                )
            GROUP BY timestamps.timestamp
        ) datapoints
    )
SELECT JSON_BUILD_OBJECT(
    'columns', (SELECT columns.list FROM columns),
    'data',    (SELECT data.points  FROM data)
) AS results;
