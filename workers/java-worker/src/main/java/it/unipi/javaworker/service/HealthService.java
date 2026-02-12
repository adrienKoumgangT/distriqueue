package it.unipi.javaworker.service;

import it.unipi.javaworker.model.WorkerMetrics;
import jakarta.annotation.PostConstruct;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.scheduling.annotation.Async;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Duration;
import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class HealthService {

    private final WorkerMetrics workerMetrics;

    private final ConnectionFactory connectionFactory;

    @Value("${distriqueue.worker.health.heartbeat-interval:10000}")
    private long heartbeatInterval;

    @Value("${distriqueue.erlang.nodes}")
    private String[] erlangNodes;

    @Value("${distriqueue.worker.health.max-failures:3}")
    private int maxFailures;

    @Getter
    private LocalDateTime lastSuccessfulHeartbeat;
    @Getter
    private int consecutiveFailures = 0;
    @Getter
    private boolean healthy = true;

    @PostConstruct
    public void init() {
        lastSuccessfulHeartbeat = LocalDateTime.now();
        log.info("HealthService initialized, heartbeat interval: {}ms", heartbeatInterval);
    }

    @Scheduled(fixedDelayString = "${distriqueue.worker.health.heartbeat-interval:10000}")
    @Async
    public void sendHeartbeat() {
        try {
            workerMetrics.updateSystemMetrics();

            boolean rabbitmqConnected = connectionFactory.createConnection().isOpen();

            // Send heartbeat to orchestrator (if configured)
            if (erlangNodes != null && erlangNodes.length > 0) {
                sendHeartbeatToOrchestrator();
            }

            // Update health status
            if (rabbitmqConnected) {
                consecutiveFailures = 0;
                lastSuccessfulHeartbeat = LocalDateTime.now();
                healthy = true;
                log.debug(
                        "Heartbeat sent successfully, load: {}/{}",
                        workerMetrics.getCurrentLoad().get(),
                        workerMetrics.getCapacity()
                );
            } else {
                consecutiveFailures++;
                log.warn("RabbitMQ connection lost, consecutive failures: {}", consecutiveFailures);
            }

            // Check if worker is unhealthy
            if (consecutiveFailures >= maxFailures) {
                healthy = false;
                log.error("Worker marked as unhealthy after {} consecutive failures",
                        consecutiveFailures);
            }

        } catch (Exception e) {
            consecutiveFailures++;
            log.error("Heartbeat failed: {}", e.getMessage());

            if (consecutiveFailures >= maxFailures) {
                healthy = false;
                log.error("Worker marked as unhealthy");
            }
        }
    }

    private void sendHeartbeatToOrchestrator() {
        // Send heartbeat to each orchestrator node
        for (String node : erlangNodes) {
            try {
                String url = buildHeartbeatUrl(node);

                WebClient.create()
                        .post()
                        .uri(url)
                        .header(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                        .bodyValue(buildHeartbeatPayload())
                        .retrieve()
                        .bodyToMono(String.class)
                        .timeout(Duration.ofSeconds(5))
                        .doOnSuccess(response ->
                                log.debug("Heartbeat to {} successful: {}", node, response))
                        .doOnError(error ->
                                log.warn("Heartbeat to {} failed: {}", node, error.getMessage()))
                        .subscribe();

            } catch (Exception e) {
                log.warn("Failed to send heartbeat to {}: {}", node, e.getMessage());
            }
        }
    }

    private String buildHeartbeatUrl(String node) {
        // Convert node@host format to http://host:8081
        String host = node.contains("@") ? node.split("@")[1] : node;
        return String.format("http://%s:8081/api/workers/heartbeat", host);
    }

    private Object buildHeartbeatPayload() {
        return new Object() {
            public final String workerId = workerMetrics.getWorkerId();
            public final String workerType = workerMetrics.getWorkerType();
            public final int capacity = workerMetrics.getCapacity();
            public final int currentLoad = workerMetrics.getCurrentLoad().get();
            public final double cpuUsage = workerMetrics.getCpuUsage();
            public final long memoryUsage = workerMetrics.getMemoryUsage();
            public final long timestamp = System.currentTimeMillis();
        };
    }

    public void resetHealth() {
        consecutiveFailures = 0;
        healthy = true;
        lastSuccessfulHeartbeat = LocalDateTime.now();
        log.info("Worker health reset");
    }

}
