package it.unipi.javaworker.model;

import lombok.*;

import java.time.LocalDateTime;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class WorkerMetrics {

    private String workerId;
    private String workerType;
    private LocalDateTime startedAt;
    private LocalDateTime lastUpdated;

    // Counters
    private AtomicLong jobsProcessed;
    private AtomicLong jobsSucceeded;
    private AtomicLong jobsFailed;
    private AtomicLong totalProcessingTimeMs;

    // Current state
    private AtomicInteger currentLoad;
    private Integer capacity;
    private Double cpuUsage;
    private Long memoryUsage;
    private Long freeMemory;

    // Queue stats
    private Integer highPriorityQueueLength;
    private Integer mediumPriorityQueueLength;
    private Integer lowPriorityQueueLength;

    // Rates
    private Double processingRate; // jobs per minute
    private Double successRate; // percentage

    public WorkerMetrics(String workerId, String workerType, Integer capacity) {
        this.workerId = workerId;
        this.workerType = workerType;
        this.capacity = capacity;
        this.startedAt = LocalDateTime.now();
        this.lastUpdated = LocalDateTime.now();
        this.jobsProcessed = new AtomicLong(0);
        this.jobsSucceeded = new AtomicLong(0);
        this.jobsFailed = new AtomicLong(0);
        this.totalProcessingTimeMs = new AtomicLong(0);
        this.currentLoad = new AtomicInteger(0);
        this.cpuUsage = 0.0;
        this.memoryUsage = 0L;
        this.freeMemory = Runtime.getRuntime().freeMemory();
    }

    public void incrementJobsProcessed() {
        jobsProcessed.incrementAndGet();
        updateLastUpdated();
    }

    public void incrementJobsSucceeded() {
        jobsSucceeded.incrementAndGet();
        updateLastUpdated();
    }

    public void incrementJobsFailed() {
        jobsFailed.incrementAndGet();
        updateLastUpdated();
    }

    public void addProcessingTime(long processingTimeMs) {
        totalProcessingTimeMs.addAndGet(processingTimeMs);
        updateLastUpdated();
    }

    public void setCurrentLoad(int load) {
        currentLoad.set(load);
        updateLastUpdated();
    }

    public void updateSystemMetrics() {
        Runtime runtime = Runtime.getRuntime();
        this.memoryUsage = runtime.totalMemory() - runtime.freeMemory();
        this.freeMemory = runtime.freeMemory();
        this.cpuUsage = getCpuUsage(); // Implement CPU usage monitoring
        updateLastUpdated();
    }

    public double getAverageProcessingTime() {
        long processed = jobsProcessed.get();
        if (processed == 0) return 0.0;
        return totalProcessingTimeMs.get() / (double) processed;
    }

    public double getSuccessRatePercentage() {
        long processed = jobsProcessed.get();
        if (processed == 0) return 100.0;
        return (jobsSucceeded.get() * 100.0) / processed;
    }

    public double getUtilizationPercentage() {
        if (capacity == null || capacity == 0) return 0.0;
        return (currentLoad.get() * 100.0) / capacity;
    }

    private void updateLastUpdated() {
        this.lastUpdated = LocalDateTime.now();
    }

    public double getCpuUsage() {
        // TODO: Simplified CPU usage calculation
        // use OSHI or similar library
        return Math.random() * 100; // Placeholder
    }

}
