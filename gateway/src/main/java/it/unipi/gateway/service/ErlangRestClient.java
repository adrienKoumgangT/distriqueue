package it.unipi.gateway.service;

import it.unipi.gateway.model.Job;
import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.Arrays;
import java.util.List;

@Service
@Slf4j
public class ErlangRestClient {

    @Value("${distriqueue.erlang.nodes}")
    private String[] erlangNodes;

    @Value("${distriqueue.erlang.rest.port:8081}")
    private int erlangRestPort;

    private WebClient webClient;
    private List<String> nodeUrls;
    private int currentNodeIndex = 0;

    @PostConstruct
    public void init() {
        // Build node URLs
        nodeUrls = Arrays.stream(erlangNodes)
                .map(node -> {
                    // Convert node@host format to http://host:port
                    String host = node.contains("@") ? node.split("@")[1] : node;
                    return String.format("http://%s:%d", host, erlangRestPort);
                })
                .toList();

        if (nodeUrls.isEmpty()) {
            log.warn("No Erlang nodes configured. Erlang communication will be disabled.");
            return;
        }

        webClient = WebClient.builder()
                .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .defaultHeader(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
                .build();

        log.info("ErlangRestClient initialized with nodes: {}", nodeUrls);
    }

    public Mono<String> registerJob(Job job) {
        if (webClient == null || nodeUrls.isEmpty()) {
            log.warn("Erlang nodes not configured, skipping job registration");
            return Mono.empty();
        }

        String currentNode = getNextNode();
        String url = currentNode + "/api/jobs/register";

        return webClient.post()
                .uri(url)
                .bodyValue(createErlangJobPayload(job))
                .retrieve()
                .bodyToMono(String.class)
                .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
                        .filter(throwable -> {
                            log.warn("Failed to register job with Erlang node {}, trying next: {}", currentNode, throwable.getMessage());
                            return true;
                        })
                        .onRetryExhaustedThrow((retryBackoffSpec, retrySignal) -> {
                            log.error("All retry attempts failed for job registration");
                            return new RuntimeException("Failed to register job with Erlang cluster");
                        })
                )
                .doOnSuccess(response ->
                        log.debug("Job {} registered with Erlang node: {}", job.getId(), response)
                )
                .doOnError(error ->
                        log.error("Failed to register job {} with Erlang: {}", job.getId(), error.getMessage())
                );
    }

    public Mono<String> updateJobStatus(String jobId, String status, String workerId) {
        if (webClient == null || nodeUrls.isEmpty()) {
            return Mono.empty();
        }

        String currentNode = getNextNode();
        String url = currentNode + "/api/jobs/" + jobId + "/status";

        var statusUpdate = new StatusUpdateRequest(status, workerId, System.currentTimeMillis());

        return webClient.put()
                .uri(url)
                .bodyValue(statusUpdate)
                .retrieve()
                .bodyToMono(String.class)
                .retryWhen(Retry.backoff(2, Duration.ofSeconds(1)));
    }

    public Mono<Void> notifyJobCancelled(String jobId) {
        if (webClient == null || nodeUrls.isEmpty()) {
            return null;
        }

        String currentNode = getNextNode();
        String url = currentNode + "/api/jobs/" + jobId + "/cancel";

        webClient.post()
                .uri(url)
                .retrieve()
                .toBodilessEntity()
                .subscribe(
                        response -> log.debug("Job cancellation notified to Erlang for job: {}", jobId),
                        error -> log.warn("Failed to notify job cancellation to Erlang: {}", error.getMessage())
                );
        return null;
    }

    public Mono<String> getClusterStatus() {
        if (webClient == null || nodeUrls.isEmpty()) {
            return Mono.just("{\"status\": \"disabled\"}");
        }

        String currentNode = getNextNode();
        String url = currentNode + "/api/cluster/status";

        return webClient.get()
                .uri(url)
                .retrieve()
                .bodyToMono(String.class)
                .timeout(Duration.ofSeconds(5))
                .onErrorReturn("{\"status\": \"unreachable\"}");
    }

    private String getNextNode() {
        // Simple round-robin load balancing
        String node = nodeUrls.get(currentNodeIndex);
        currentNodeIndex = (currentNodeIndex + 1) % nodeUrls.size();
        return node;
    }

    private ErlangJobPayload createErlangJobPayload(Job job) {
        return ErlangJobPayload.builder()
                .id(job.getId())
                .type(job.getType())
                .priority(job.getPriority().getValue())
                .payload(job.getPayload())
                .timeout(job.getExecutionTimeout())
                .maxRetries(job.getMaxRetries())
                .createdAt(job.getCreatedAt().toString())
                .build();
    }

    // Inner DTO classes for Erlang communication
    @lombok.Data
    @lombok.Builder
    private static class ErlangJobPayload {
        private String id;
        private String type;
        private int priority;
        private Object payload;
        private int timeout;
        private int maxRetries;
        private String createdAt;
    }

    @lombok.Data
    @lombok.AllArgsConstructor
    private static class StatusUpdateRequest {
        private String status;
        private String workerId;
        private long timestamp;
    }

}
