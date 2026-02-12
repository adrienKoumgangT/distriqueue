package it.unipi.gateway.service;

import it.unipi.gateway.model.WorkerHealth;
import it.unipi.gateway.model.WorkerStatus;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Slf4j
@Service
@RequiredArgsConstructor
public class WorkerHealthMonitor {

    private final JobService jobService;


    private final Map<String, WorkerHealth> workerHealthMap = new ConcurrentHashMap<>();
    private final Map<String, LocalDateTime> workerLastSeen = new ConcurrentHashMap<>();

    private static final long HEALTH_CHECK_INTERVAL = 30000; // 30 seconds
    private static final long WORKER_TIMEOUT = 120000; // 2 minutes

    @PostConstruct
    public void init() {
        log.info("WorkerHealthMonitor initialized");
    }

    @PreDestroy
    public void cleanup() {
        workerHealthMap.clear();
        workerLastSeen.clear();
    }

    public void registerWorkerHeartbeat(
            String workerId,
            String workerType,
            int capacity,
            int load
    ) {
        WorkerHealth health = workerHealthMap.computeIfAbsent(
                workerId,
                id -> new WorkerHealth(id, workerType)
        );

        health.setLastHeartbeat(LocalDateTime.now());
        health.setCapacity(capacity);
        health.setCurrentLoad(load);
        health.setStatus(WorkerStatus.ACTIVE);

        workerLastSeen.put(workerId, LocalDateTime.now());

        log.debug(
                "Heartbeat received from worker {}: capacity={}, load={}",
                workerId,
                capacity,
                load
        );
    }

    public WorkerHealth getWorkerHealth(String workerId) {
        return workerHealthMap.get(workerId);
    }

    public Map<String, WorkerHealth> getAllWorkerHealth() {
        return new ConcurrentHashMap<>(workerHealthMap);
    }

    @Scheduled(fixedDelay = HEALTH_CHECK_INTERVAL)
    public void checkWorkerHealth() {
        LocalDateTime now = LocalDateTime.now();

        workerHealthMap.forEach((workerId, health) -> {
            LocalDateTime lastHeartbeat = health.getLastHeartbeat();

            if (lastHeartbeat != null && lastHeartbeat.plus(WORKER_TIMEOUT , ChronoUnit.MILLIS).isBefore(now)) {
                log.warn(
                        "Worker {} has not sent heartbeat for {} seconds. Marking as UNRESPONSIVE.",
                        workerId,
                        java.time.Duration.between(lastHeartbeat, now).getSeconds()
                );

                health.setStatus(WorkerStatus.UNRESPONSIVE);

                // Reassign jobs from unresponsive worker
                reassignJobsFromWorker(workerId);
            }
        });

        cleanupOldWorkers();
    }

    private void reassignJobsFromWorker(String workerId) {
        log.info("Reassigning jobs from unresponsive worker: {}", workerId);

        // TODO: this would query jobs assigned to this worker and reschedule them.

        log.debug("Job reassignment logic would execute here for worker: {}", workerId);
    }

    private void cleanupOldWorkers() {
        LocalDateTime cleanupThreshold = LocalDateTime.now().minusHours(24);

        workerLastSeen.entrySet().removeIf(entry -> {
            if (entry.getValue().isBefore(cleanupThreshold)) {
                String workerId = entry.getKey();
                workerHealthMap.remove(workerId);
                log.info("Cleaned up old worker: {}", workerId);
                return true;
            }
            return false;
        });
    }

}
