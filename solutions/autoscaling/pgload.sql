SELECT SUM(val)
FROM (
    SELECT SIN(RADIANS(number)) + COS(RADIANS(number)) AS val
    FROM generate_series(1, 300000000) AS number
) AS subquery;