package io.aiven.ingest;

import io.aiven.ingest.tier.IngestTier;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** The skeleton wires up: context boots and all six ladder rungs (plus the off-ladder buffered REST pipeline, tier 0) are present. */
@SpringBootTest
class ApplicationContextIntegrationTest extends AbstractClickHouseIntegrationTest {

    @Autowired
    List<IngestTier> tiers;

    @Test
    void allTiersAreRegistered() {
        assertThat(tiers.stream().map(IngestTier::tier).sorted().toList())
                .containsExactly(0, 1, 2, 3, 4, 5, 6);
    }
}
