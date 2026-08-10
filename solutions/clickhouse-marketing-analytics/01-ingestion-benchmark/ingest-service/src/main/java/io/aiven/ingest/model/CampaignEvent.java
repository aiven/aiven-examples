package io.aiven.ingest.model;

import java.time.Instant;

/**
 * One row of campaign_events (see shared/schema/01_campaign_events.sql).
 * Field order matches the DDL column order; every tier serializes from this
 * record so all benchmark numbers move the exact same payload.
 */
public record CampaignEvent(
        Instant eventTime,
        String eventType,
        String userId,
        String sessionId,
        String campaignId,
        String channel,
        String source,
        String medium,
        String adGroup,
        String keyword,
        String landingPage,
        Double conversionValue,
        String currency,
        String country,
        String deviceType,
        String properties) {

    public static final String[] COLUMNS = {
            "event_time", "event_type", "user_id", "session_id", "campaign_id",
            "channel", "source", "medium", "ad_group", "keyword", "landing_page",
            "conversion_value", "currency", "country", "device_type", "properties"
    };
}
