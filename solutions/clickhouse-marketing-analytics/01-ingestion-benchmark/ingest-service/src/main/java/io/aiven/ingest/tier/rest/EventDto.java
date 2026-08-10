package io.aiven.ingest.tier.rest;

import io.aiven.ingest.model.CampaignEvent;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;

import java.time.Instant;

/**
 * Wire format of POST /events: snake_case field names matching the
 * campaign_events columns. event_time is optional (defaults to arrival time -
 * mobile SDKs that batch offline events should send their own).
 */
@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
public record EventDto(
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

    public CampaignEvent toCampaignEvent() {
        return new CampaignEvent(
                eventTime != null ? eventTime : Instant.now(),
                eventType,
                userId,
                sessionId,
                campaignId != null ? campaignId : "",
                channel,
                source,
                medium,
                adGroup,
                keyword,
                landingPage,
                conversionValue,
                currency,
                country,
                deviceType,
                properties != null ? properties : "{}");
    }
}
