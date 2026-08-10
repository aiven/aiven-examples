package io.aiven.ingest.tier.tier5;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.IngestTier;
import com.clickhouse.client.api.Client;
import com.clickhouse.client.api.data_formats.RowBinaryFormatWriter;
import com.clickhouse.client.api.insert.InsertResponse;
import com.clickhouse.client.api.insert.InsertSettings;
import com.clickhouse.client.api.metadata.TableSchema;
import com.clickhouse.data.ClickHouseFormat;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/**
 * Tier 5 - official com.clickhouse client-v2: the batch is serialized on the
 * client (RowBinary by default) and shipped as one LZ4-compressed HTTP body,
 * so the server skips SQL parsing entirely and the wire cost drops ~5x vs
 * inline VALUES. This is also the body-separated insert path where server-side
 * async_insert actually engages from Java (unlike JDBC inline VALUES - see
 * README findings). Compare formats with --format=JSONEachRow.
 */
@Service
public class NativeStreamService implements IngestTier {

    static final String TABLE = "campaign_events";

    private final Client client;
    private final int batchSize;
    private final boolean jsonEachRow;
    private final InsertSettings insertSettings = new InsertSettings();
    private volatile TableSchema schema;

    public NativeStreamService(@Lazy Client client,
                               @Value("${ingest.batch-size:10000}") int batchSize,
                               @Value("${ingest.format:RowBinary}") String format) {
        this.client = client;
        this.batchSize = batchSize;
        this.jsonEachRow = "JSONEachRow".equalsIgnoreCase(format);
        if (!jsonEachRow && !"RowBinary".equalsIgnoreCase(format)) {
            throw new IllegalArgumentException("ingest.format must be RowBinary or JSONEachRow, got: " + format);
        }
        if (jsonEachRow) {
            // DateTime64 in JSON only parses integers or strings; best_effort
            // makes ISO-8601 with 'Z' unambiguous regardless of server timezone.
            insertSettings.serverSetting("date_time_input_format", "best_effort");
        }
    }

    @Override
    public int tier() {
        return 5;
    }

    @Override
    public String description() {
        return "client-v2 " + (jsonEachRow ? "JSONEachRow" : "RowBinary")
                + " streaming + LZ4, " + batchSize + " rows/batch";
    }

    @Override
    public long ingest(Iterator<CampaignEvent> events, BenchmarkReporter reporter) {
        long inserted = 0;
        List<CampaignEvent> batch = new ArrayList<>(batchSize);
        while (events.hasNext()) {
            batch.add(events.next());
            if (batch.size() == batchSize || !events.hasNext()) {
                inserted += flushBatch(batch, reporter);
                batch.clear();
            }
        }
        return inserted;
    }

    /** One serialized batch = one insert = one part. Also tier 6's write path. */
    public long flushBatch(List<CampaignEvent> batch, BenchmarkReporter reporter) {
        // The ladder runs with the tier's own settings so benchmark numbers
        // reflect an unmodified server (see README finding 8).
        return flushBatch(batch, reporter, insertSettings);
    }

    /** Same path with caller-supplied settings - the Valkey flusher pins async_insert=0 here. */
    public long flushBatch(List<CampaignEvent> batch, BenchmarkReporter reporter, InsertSettings settings) {
        long t0 = System.nanoTime();
        try {
            byte[] payload = jsonEachRow ? serializeJsonEachRow(batch) : serializeRowBinary(batch);
            ClickHouseFormat format = jsonEachRow ? ClickHouseFormat.JSONEachRow : ClickHouseFormat.RowBinary;
            try (InsertResponse ignored = client
                    .insert(TABLE, new ByteArrayInputStream(payload), format, settings)
                    .get()) {
                reporter.recordFlush(batch.size(), System.nanoTime() - t0);
                return batch.size();
            }
        } catch (Exception ex) {
            if (ex instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            reporter.recordError(ex);
            return 0;
        }
    }

    private byte[] serializeRowBinary(List<CampaignEvent> batch) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(batch.size() * 160);
        RowBinaryFormatWriter w = new RowBinaryFormatWriter(out, tableSchema(), ClickHouseFormat.RowBinary);
        for (CampaignEvent e : batch) {
            w.setDateTime("event_time", e.eventTime().atZone(ZoneOffset.UTC));
            w.setString("event_type", e.eventType());
            w.setString("user_id", e.userId());
            w.setString("session_id", e.sessionId());
            w.setString("campaign_id", e.campaignId());
            w.setString("channel", e.channel());
            w.setValue("source", e.source());
            w.setValue("medium", e.medium());
            w.setValue("ad_group", e.adGroup());
            w.setValue("keyword", e.keyword());
            w.setValue("landing_page", e.landingPage());
            w.setValue("conversion_value", e.conversionValue());
            w.setValue("currency", e.currency());
            w.setString("country", e.country());
            w.setString("device_type", e.deviceType());
            w.setString("properties", e.properties());
            w.commitRow();
        }
        return out.toByteArray();
    }

    private TableSchema tableSchema() {
        TableSchema s = schema;
        if (s == null) {
            synchronized (this) {
                if (schema == null) {
                    schema = client.getTableSchema(TABLE);
                }
                s = schema;
            }
        }
        return s;
    }

    private byte[] serializeJsonEachRow(List<CampaignEvent> batch) {
        StringBuilder sb = new StringBuilder(batch.size() * 320);
        for (CampaignEvent e : batch) {
            sb.append("{\"event_time\":\"").append(e.eventTime()).append('"');
            field(sb, "event_type", e.eventType());
            field(sb, "user_id", e.userId());
            field(sb, "session_id", e.sessionId());
            field(sb, "campaign_id", e.campaignId());
            field(sb, "channel", e.channel());
            field(sb, "source", e.source());
            field(sb, "medium", e.medium());
            field(sb, "ad_group", e.adGroup());
            field(sb, "keyword", e.keyword());
            field(sb, "landing_page", e.landingPage());
            sb.append(",\"conversion_value\":").append(e.conversionValue() == null ? "null" : e.conversionValue());
            field(sb, "currency", e.currency());
            field(sb, "country", e.country());
            field(sb, "device_type", e.deviceType());
            field(sb, "properties", e.properties());
            sb.append("}\n");
        }
        return sb.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
    }

    private static void field(StringBuilder sb, String name, String value) {
        sb.append(",\"").append(name).append("\":");
        if (value == null) {
            sb.append("null");
            return;
        }
        sb.append('"');
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                }
            }
        }
        sb.append('"');
    }
}
