package io.aiven.ingest;

import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.clickhouse.ClickHouseContainer;
import org.testcontainers.utility.DockerImageName;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.util.List;

/**
 * Shared ClickHouse container for all integration tests. The container is
 * started once per JVM (singleton pattern), the campaign_analytics database is
 * created, and the real DDL files from ../../shared/schema are applied verbatim - the tests
 * verify the exact SQL that will be handed over, not a copy.
 */
public abstract class AbstractClickHouseIntegrationTest {

    static final String DATABASE = "campaign_analytics";

    static final ClickHouseContainer CLICKHOUSE = new ClickHouseContainer(
            DockerImageName.parse("clickhouse/clickhouse-server:25.3"));

    static {
        CLICKHOUSE.start();
        try {
            applyDdl();
        } catch (Exception e) {
            throw new IllegalStateException("Failed to apply DDL to test container", e);
        }
    }

    @DynamicPropertySource
    static void clickhouseProperties(DynamicPropertyRegistry registry) {
        registry.add("clickhouse.host", CLICKHOUSE::getHost);
        registry.add("clickhouse.port", () -> CLICKHOUSE.getMappedPort(8123));
        registry.add("clickhouse.ssl", () -> false);
        registry.add("clickhouse.database", () -> DATABASE);
        registry.add("clickhouse.username", CLICKHOUSE::getUsername);
        registry.add("clickhouse.password", CLICKHOUSE::getPassword);
        registry.add("ingest.tier", () -> -1); // never auto-run a benchmark inside tests
    }

    /** Connection to the campaign_analytics database inside the container. */
    static Connection connect() throws Exception {
        String url = "jdbc:ch://" + CLICKHOUSE.getHost() + ":" + CLICKHOUSE.getMappedPort(8123) + "/" + DATABASE;
        return DriverManager.getConnection(url, CLICKHOUSE.getUsername(), CLICKHOUSE.getPassword());
    }

    private static void applyDdl() throws Exception {
        String setupUrl = "jdbc:ch://" + CLICKHOUSE.getHost() + ":" + CLICKHOUSE.getMappedPort(8123) + "/default";
        try (Connection conn = DriverManager.getConnection(setupUrl, CLICKHOUSE.getUsername(), CLICKHOUSE.getPassword());
             Statement stmt = conn.createStatement()) {
            stmt.execute("CREATE DATABASE IF NOT EXISTS " + DATABASE);
        }
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            for (String file : List.of("01_campaign_events.sql", "02_daily_campaign_rollup.sql")) {
                for (String sql : readStatements(ddlDir().resolve(file))) {
                    stmt.execute(sql);
                }
            }
        }
    }

    /** Locate shared/schema whether tests run from ingest-service/ (Maven) or the repo root (IDE). */
    private static Path ddlDir() {
        Path candidate = Path.of("..", "..", "shared", "schema");
        if (Files.isDirectory(candidate)) return candidate;
        candidate = Path.of("shared", "schema");
        if (Files.isDirectory(candidate)) return candidate;
        throw new IllegalStateException("Cannot locate the shared/schema/ directory from " + Path.of("").toAbsolutePath());
    }

    /** Strip -- comments and split on ';' (the DDL files keep statements simple by design). */
    private static List<String> readStatements(Path file) throws Exception {
        String noComments = Files.readAllLines(file).stream()
                .filter(line -> !line.trim().startsWith("--"))
                .reduce("", (a, b) -> a + "\n" + b);
        return List.of(noComments.split(";")).stream()
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
    }
}
