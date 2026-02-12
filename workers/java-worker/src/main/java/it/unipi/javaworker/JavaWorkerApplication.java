package it.unipi.javaworker;

import it.unipi.javaworker.model.WorkerMetrics;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.retry.annotation.EnableRetry;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

@Slf4j
@EnableRetry
@EnableAsync
@EnableScheduling
@SpringBootApplication
public class JavaWorkerApplication {

    @Autowired
    private WorkerMetrics workerMetrics;

    public static void main(String[] args) {
        SpringApplication.run(JavaWorkerApplication.class, args);
    }

    @PostConstruct
    public void init() {
        log.info("==========================================");
        log.info("DistriQueue Java Worker Starting");
        log.info("Worker ID: {}", workerMetrics.getWorkerId());
        log.info("Worker Type: {}", workerMetrics.getWorkerType());
        log.info("Capacity: {}", workerMetrics.getCapacity());
        log.info("==========================================");
    }

    @PreDestroy
    public void cleanup() {
        log.info("==========================================");
        log.info("DistriQueue Java Worker Shutting Down");
        log.info("Final Statistics:");
        log.info("  Jobs Processed: {}", workerMetrics.getJobsProcessed().get());
        log.info("  Jobs Succeeded: {}", workerMetrics.getJobsSucceeded().get());
        log.info("  Jobs Failed: {}", workerMetrics.getJobsFailed().get());
        log.info("  Success Rate: {}%", workerMetrics.getSuccessRatePercentage());
        log.info("  Avg Processing Time: {}ms", workerMetrics.getAverageProcessingTime());
        log.info("==========================================");
    }
}
