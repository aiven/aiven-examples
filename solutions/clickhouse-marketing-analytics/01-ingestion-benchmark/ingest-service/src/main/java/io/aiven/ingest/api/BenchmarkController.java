package io.aiven.ingest.api;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.List;
import java.util.Map;

/**
 * Remote control for the tier ladder, for deployments where there is no
 * terminal (Aiven Apps next to the ClickHouse service):
 *
 *   POST /benchmarks {"tier":4,"rows":1000000}   -> 202 + run id
 *   GET  /benchmarks/{id}                        -> live progress / final result
 *   GET  /benchmarks                             -> all runs this process
 *
 * One run at a time; a POST while busy returns 409 with the active run's id.
 */
@RestController
public class BenchmarkController {

    private final BenchmarkRunService service;

    public BenchmarkController(BenchmarkRunService service) {
        this.service = service;
    }

    @PostMapping("/benchmarks")
    public ResponseEntity<Map<String, Object>> start(@RequestBody BenchmarkRequest request) {
        BenchmarkRun run = service.start(request);
        return ResponseEntity.accepted()
                .location(URI.create("/benchmarks/" + run.id()))
                .body(run.toStatus());
    }

    @GetMapping("/benchmarks")
    public List<Map<String, Object>> list() {
        return service.all().stream().map(BenchmarkRun::toStatus).toList();
    }

    @GetMapping("/benchmarks/{id}")
    public ResponseEntity<Map<String, Object>> get(@PathVariable String id) {
        BenchmarkRun run = service.get(id);
        return run == null
                ? ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "no run with id " + id))
                : ResponseEntity.ok(run.toStatus());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, Object>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(BenchmarkRunService.BenchmarkBusyException.class)
    ResponseEntity<Map<String, Object>> busy(BenchmarkRunService.BenchmarkBusyException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(Map.of("error", e.getMessage(),
                        "active_run", e.activeRun().toStatus()));
    }
}
