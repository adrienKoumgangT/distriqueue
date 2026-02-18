package it.unipi.javaworker.config;

import it.unipi.javaworker.model.WorkerMetrics;
import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.List;
import java.util.concurrent.Executor;
import java.util.concurrent.ThreadPoolExecutor;

@Slf4j
@EnableAsync
@Configuration
@EnableScheduling
public class WorkerConfig {

    @Value("${distriqueue.worker.id}")
    private String workerId;

    @Value("${distriqueue.worker.type}")
    private String workerType;

    @Value("${distriqueue.worker.capacity}")
    private Integer capacity;

    @Value("${distriqueue.worker.queues:job.high,job.medium,job.low}")
    private List<String> queues;

    @Value("${distriqueue.worker.job.concurrency}")
    private Integer concurrency;

    @PostConstruct
    public void init() {
        log.info("Worker Configuration:");
        log.info("  Worker ID: {}", workerId);
        log.info("  Worker Type: {}", workerType);
        log.info("  Capacity: {}", capacity);
        log.info("  Consuming from queues: {}", queues);
        log.info("  Job Concurrency: {}", concurrency);
    }

    @Bean
    public WorkerMetrics workerMetrics() {
        log.info("Creating WorkerMetrics for worker: {}", workerId);
        return new WorkerMetrics(workerId, workerType, capacity);
    }

    @Bean("jobProcessingExecutor")
    public Executor jobProcessingExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(concurrency);
        executor.setMaxPoolSize(concurrency * 2);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("job-processor-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        log.info("Created job processing executor with corePoolSize: {}", concurrency);
        return executor;
    }

    @Bean("heartbeatExecutor")
    public Executor heartbeatExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(1);
        executor.setMaxPoolSize(1);
        executor.setThreadNamePrefix("heartbeat-");
        executor.initialize();
        return executor;
    }

}
