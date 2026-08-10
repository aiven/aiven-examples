-- Q7 Email campaign analytics (the most MoEngage-shaped chart): sends, opens,
-- clicks, open rate and click-to-open rate BY HOUR, per the blog. The hourly
-- grain is the point -- campaign sends arrive as bursts, and opens trail them
-- with the decay curve. Last 7 days of data; add a campaign_id
-- filter to drill into one campaign's send spike.
SELECT
    toStartOfHour(event_time)                                     AS hour,
    countIf(event_type = 'email_send')                            AS sends,
    countIf(event_type = 'email_open')                            AS opens,
    countIf(event_type = 'email_click')                           AS clicks,
    round(opens  / nullIf(sends, 0) * 100, 1)                     AS open_rate_pct,
    round(clicks / nullIf(opens, 0) * 100, 1)                     AS click_to_open_pct
FROM campaign_events
WHERE channel = 'email'
  AND event_type IN ('email_send', 'email_open', 'email_click')
  AND event_time >= (SELECT max(event_time) FROM campaign_events) - INTERVAL 7 DAY
GROUP BY hour
ORDER BY hour;
