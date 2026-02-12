package it.unipi.javaworker.service;

import io.micrometer.core.instrument.*;
import it.unipi.javaworker.model.WorkerMetrics;
import jakarta.annotation.PostConstruct;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.concurrent.TimeUnit;

@Slf4j
@Service
@RequiredArgsConstructor
public class MetricsService {

    @Getter
    private final WorkerMetrics workerMetrics;

    private final MeterRegistry meterRegistry;

    @Value("${distriqueue.worker.metrics.enabled:true}")
    private boolean metricsEnabled;

    @Value("${distriqueue.worker.metrics.export-interval:30000}")
    private long exportInterval;

    // Micrometer metrics
    private Counter jobsProcessedCounter;
    private Counter jobsSucceededCounter;
    private Counter jobsFailedCounter;
    private Timer jobProcessingTimer;
    private Gauge currentLoadGauge;
    private Gauge capacityGauge;
    private Gauge cpuUsageGauge;
    private Gauge memoryUsageGauge;
    private Gauge successRateGauge;

    @PostConstruct
    public void init() {
        if (!metricsEnabled) {
            log.info("Metrics export disabled");
            return;
        }

        log.info("Initializing metrics service, export interval: {}ms", exportInterval);

        String workerId = workerMetrics.getWorkerId();

        jobsProcessedCounter = Counter.builder("distriqueue.worker.jobs.processed")
                .description("Total number of jobs processed")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        jobsSucceededCounter = Counter.builder("distriqueue.worker.jobs.succeeded")
                .description("Total number of jobs succeeded")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        jobsFailedCounter = Counter.builder("distriqueue.worker.jobs.failed")
                .description("Total number of jobs failed")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        jobProcessingTimer = Timer.builder("distriqueue.worker.job.processing.time")
                .description("Job processing time")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(meterRegistry);

        // Gauges
        currentLoadGauge = Gauge.builder("distriqueue.worker.current.load",
                        workerMetrics, m -> m.getCurrentLoad().get())
                .description("Current worker load")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        capacityGauge = Gauge.builder("distriqueue.worker.capacity",
                        workerMetrics, WorkerMetrics::getCapacity)
                .description("Worker capacity")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        cpuUsageGauge = Gauge.builder("distriqueue.worker.cpu.usage",
                        workerMetrics, WorkerMetrics::getCpuUsage)
                .description("CPU usage percentage")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        memoryUsageGauge = Gauge.builder("distriqueue.worker.memory.usage",
                        workerMetrics, WorkerMetrics::getMemoryUsage)
                .description("Memory usage in bytes")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        successRateGauge = Gauge.builder("distriqueue.worker.success.rate",
                        workerMetrics, WorkerMetrics::getSuccessRatePercentage)
                .description("Job success rate percentage")
                .tag("worker_id", workerId)
                .tag("worker_type", workerMetrics.getWorkerType())
                .register(meterRegistry);

        log.info("Metrics service initialized for worker: {}", workerId);
    }

    @Scheduled(fixedDelayString = "${distriqueue.worker.metrics.export-interval:30000}")
    public void exportMetrics() {
        if (!metricsEnabled) return;

        try {
            long processed = workerMetrics.getJobsProcessed().get();
            long succeeded = workerMetrics.getJobsSucceeded().get();
            long failed = workerMetrics.getJobsFailed().get();

            workerMetrics.updateSystemMetrics();

            log.debug(
                    "Metrics exported: processed={}, succeeded={}, failed={}, load={}/{}",
                    processed,
                    succeeded,
                    failed,
                    workerMetrics.getCurrentLoad().get(),
                    workerMetrics.getCapacity()
            );

        } catch (Exception e) {
            log.error("Failed to export metrics: {}", e.getMessage());
        }
    }

    public void recordJobProcessingTime(long processingTimeMs) {
        if (metricsEnabled && jobProcessingTimer != null) {
            jobProcessingTimer.record(processingTimeMs, TimeUnit.MILLISECONDS);
        }
    }

    public void incrementJobsProcessed() {
        if (metricsEnabled && jobsProcessedCounter != null) {
            jobsProcessedCounter.increment();
        }
    }

    public void incrementJobsSucceeded() {
        if (metricsEnabled && jobsSucceededCounter != null) {
            jobsSucceededCounter.increment();
        }
    }

    public void incrementJobsFailed() {
        if (metricsEnabled && jobsFailedCounter != null) {
            jobsFailedCounter.increment();
        }
    }

}
