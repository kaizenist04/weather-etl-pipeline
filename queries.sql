-- ============ BASIC ANALYSIS ============

-- 1. Average and max temperature per city
SELECT city,
       ROUND(AVG(temp_avg_c), 2) AS avg_temp,
       MAX(temp_max_c)           AS highest_temp
FROM daily_weather
GROUP BY city
ORDER BY avg_temp DESC;

-- 2. Total rainfall per city (cities with any rain)
SELECT city, ROUND(SUM(rainfall_mm), 1) AS total_rain_mm
FROM daily_weather
GROUP BY city
HAVING SUM(rainfall_mm) > 0
ORDER BY total_rain_mm DESC;

-- 3. Hottest day for each city (window function)
SELECT city, date, temp_max_c
FROM (
    SELECT city, date, temp_max_c,
           ROW_NUMBER() OVER (PARTITION BY city ORDER BY temp_max_c DESC) AS rn
    FROM daily_weather
)
WHERE rn = 1;

-- 4. Day-over-day temperature change (LAG)
SELECT city, date, temp_avg_c,
       ROUND(temp_avg_c - LAG(temp_avg_c) OVER (PARTITION BY city ORDER BY date), 2) AS change_vs_prev_day
FROM daily_weather
ORDER BY city, date;

-- 5. Days hotter than that city's own average (CTE + JOIN)
WITH city_avg AS (
    SELECT city, AVG(temp_avg_c) AS avg_t FROM daily_weather GROUP BY city
)
SELECT w.city, COUNT(*) AS days_above_avg
FROM daily_weather w
JOIN city_avg c ON w.city = c.city
WHERE w.temp_avg_c > c.avg_t
GROUP BY w.city;

-- ============ RAINFALL ============

-- 6. Rainy vs dry days per city (CASE WHEN)
SELECT city,
       SUM(CASE WHEN rainfall_mm > 0 THEN 1 ELSE 0 END) AS rainy_days,
       SUM(CASE WHEN rainfall_mm = 0 THEN 1 ELSE 0 END) AS dry_days,
       ROUND(100.0 * SUM(CASE WHEN rainfall_mm > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS rainy_day_pct
FROM daily_weather
GROUP BY city
ORDER BY rainy_days DESC;

-- 7. Top 3 heaviest rainfall days per city (RANK)
SELECT city, date, rainfall_mm, rain_rank
FROM (
    SELECT city, date, rainfall_mm,
           RANK() OVER (PARTITION BY city ORDER BY rainfall_mm DESC) AS rain_rank
    FROM daily_weather
)
WHERE rain_rank <= 3 AND rainfall_mm > 0
ORDER BY city, rain_rank;

-- 8. Running (cumulative) rainfall per city
SELECT city, date, rainfall_mm,
       ROUND(SUM(rainfall_mm) OVER (PARTITION BY city ORDER BY date), 1) AS cumulative_rain_mm
FROM daily_weather
ORDER BY city, date;

-- ============ TEMPERATURE TRENDS ============

-- 9. 7-day moving average temperature (smooths daily noise)
SELECT city, date, temp_avg_c,
       ROUND(AVG(temp_avg_c) OVER (
           PARTITION BY city ORDER BY date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS moving_avg_7d
FROM daily_weather
ORDER BY city, date;

-- 10. Days with the widest temperature swing (max minus min)
SELECT city, date,
       ROUND(temp_max_c - temp_min_c, 1) AS daily_range_c
FROM daily_weather
ORDER BY daily_range_c DESC
LIMIT 10;

-- 11. Classify each day as Hot, Warm or Mild, then count per city
SELECT city,
       CASE WHEN temp_max_c >= 35 THEN 'Hot (35C+)'
            WHEN temp_max_c >= 30 THEN 'Warm (30-35C)'
            ELSE 'Mild (<30C)' END AS day_type,
       COUNT(*) AS num_days
FROM daily_weather
GROUP BY city, day_type
ORDER BY city, num_days DESC;

-- 12. Weekly average temperature per city
SELECT city,
       strftime('%Y-W%W', date) AS week,
       ROUND(AVG(temp_avg_c), 2) AS weekly_avg_temp,
       ROUND(SUM(rainfall_mm), 1) AS weekly_rain_mm
FROM daily_weather
GROUP BY city, week
ORDER BY city, week;

-- ============ CITY COMPARISON ============

-- 13. Each city's average versus the overall average (CTE)
WITH overall AS (
    SELECT AVG(temp_avg_c) AS overall_avg FROM daily_weather
)
SELECT d.city,
       ROUND(AVG(d.temp_avg_c), 2) AS city_avg,
       ROUND(o.overall_avg, 2)     AS overall_avg,
       ROUND(AVG(d.temp_avg_c) - o.overall_avg, 2) AS diff_from_overall
FROM daily_weather d
CROSS JOIN overall o
GROUP BY d.city
ORDER BY diff_from_overall DESC;

-- 14. Rank cities by average temperature (RANK)
SELECT city, avg_temp,
       RANK() OVER (ORDER BY avg_temp DESC) AS temp_rank
FROM (
    SELECT city, ROUND(AVG(temp_avg_c), 2) AS avg_temp
    FROM daily_weather
    GROUP BY city
);

-- 15. Dates where Mumbai was hotter than Delhi (self-join)
SELECT m.date,
       m.temp_avg_c AS mumbai_temp,
       d.temp_avg_c AS delhi_temp,
       ROUND(m.temp_avg_c - d.temp_avg_c, 2) AS difference
FROM daily_weather m
JOIN daily_weather d ON m.date = d.date
WHERE m.city = 'Mumbai' AND d.city = 'Delhi'
  AND m.temp_avg_c > d.temp_avg_c
ORDER BY difference DESC
LIMIT 10;

-- ============ DATA QUALITY ============

-- 16. Row count and date range per city (completeness check)
SELECT city,
       COUNT(*)  AS total_rows,
       MIN(date) AS first_date,
       MAX(date) AS last_date
FROM daily_weather
GROUP BY city;

-- 17. Any city/date duplicates or missing values (should return 0 rows)
SELECT city, date, COUNT(*) AS copies
FROM daily_weather
GROUP BY city, date
HAVING COUNT(*) > 1;
