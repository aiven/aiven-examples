package io.aiven.loadgen.api;

import io.aiven.loadgen.run.LoadTestRequest;
import io.aiven.loadgen.run.LoadTestRun;
import io.aiven.loadgen.run.LoadTestService;
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
 * Remote control for load tests - the reason this generator is a service:
 * deployed on Aiven Apps next to the ingest service there is no terminal, so
 * runs are fired and observed entirely over HTTP.
 */
@RestController
public class LoadTestController {

    private final LoadTestService service;

    public LoadTestController(LoadTestService service) {
        this.service = service;
    }

    @PostMapping("/loadtests")
    public ResponseEntity<LoadTestRun> start(@RequestBody(required = false) LoadTestRequest request) {
        LoadTestRun run = service.start(request);
        return ResponseEntity.accepted()
                .location(URI.create("/loadtests/" + run.id()))
                .body(run);
    }

    @GetMapping("/loadtests/{id}")
    public ResponseEntity<LoadTestRun> get(@PathVariable String id) {
        LoadTestRun run = service.get(id);
        return run != null ? ResponseEntity.ok(run) : ResponseEntity.notFound().build();
    }

    @GetMapping("/loadtests")
    public List<LoadTestRun> all() {
        return service.all();
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(LoadTestService.LoadTestBusyException.class)
    ResponseEntity<LoadTestRun> busy(LoadTestService.LoadTestBusyException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(e.activeRun());
    }
}
