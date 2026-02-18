package it.unipi.javaworker.consumer;

import it.unipi.javaworker.model.WorkerMetrics;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@Component
@RequiredArgsConstructor
public class PriorityJobConsumer {

    private final WorkerMetrics workerMetrics;

    @Value("${distriqueue.worker.capacity}")
    private Integer capacity;

    private Map<String, Integer> queueStats = new HashMap<>();

    @PostConstruct
    public void init() {
        log.info("PriorityJobConsumer initialized with capacity: {}", capacity);
    }

    // @RabbitListener(queues = "${queue.high:job.high}")
    public void consumeHighPriorityJob(Object job) {
        processJob("high", job);
    }

    // @RabbitListener(queues = "${queue.medium:job.medium}")
    public void consumeMediumPriorityJob(Object job) {
        processJob("medium", job);
    }

    // @RabbitListener(queues = "${queue.low:job.low}")
    public void consumeLowPriorityJob(Object job) {
        processJob("low", job);
    }

    private void processJob(String priority, Object job) {
        int currentLoad = workerMetrics.getCurrentLoad().get();

        if (currentLoad >= capacity) {
            log.warn(
                    "Worker at full capacity ({}), cannot process {} priority job",
                    currentLoad,
                    priority
            );
            return;
        }

        queueStats.put(priority, queueStats.getOrDefault(priority, 0) + 1);

        log.debug(
                "Processing {} priority job, current load: {}/{}",
                priority,
                currentLoad,
                capacity
        );
    }

    public Map<String, Integer> getQueueStats() {
        return new HashMap<>(queueStats);
    }

    public void resetQueueStats() {
        queueStats.clear();
    }

}
