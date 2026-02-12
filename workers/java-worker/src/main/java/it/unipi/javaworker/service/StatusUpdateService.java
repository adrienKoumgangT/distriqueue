package it.unipi.javaworker.service;

import it.unipi.javaworker.model.JobResult;
import it.unipi.javaworker.util.RetryUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;

@Slf4j
@Service
public class StatusUpdateService {

    @Value("${distriqueue.worker.status.update-url}")
    private String statusUpdateUrl;

    @Value("${distriqueue.worker.status.retry-attempts:3}")
    private int retryAttempts;

    @Value("${distriqueue.worker.status.retry-delay:1000}")
    private long retryDelay;

    private final WebClient webClient;

    public StatusUpdateService() {
        this.webClient = WebClient.builder()
                .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .defaultHeader(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
                .build();
    }

    @Async
    public void sendStatusUpdate(JobResult jobResult) {
        if (statusUpdateUrl == null || statusUpdateUrl.isEmpty()) {
            log.warn("Status update URL not configured, skipping update for job: {}", jobResult.getJobId());
            return;
        }

        String jobId = jobResult.getJobId();

        log.debug("[{}] Sending status update: {}", jobId, jobResult.getStatus());

        webClient.post()
                .uri(statusUpdateUrl)
                .bodyValue(jobResult)
                .retrieve()
                .bodyToMono(String.class)
                .retryWhen(RetryUtils.exponentialBackoff(retryAttempts, Duration.ofMillis(retryDelay)))
                .subscribe(
                        response -> log.debug("[{}] Status update sent successfully: {}", jobId, response),
                        error -> log.error("[{}] Failed to send status update: {}", jobId, error.getMessage())
                );
    }

    public Mono<String> sendStatusUpdateSync(JobResult jobResult) {
        if (statusUpdateUrl == null || statusUpdateUrl.isEmpty()) {
            log.warn("Status update URL not configured");
            return Mono.just("skipped");
        }

        return webClient.post()
                .uri(statusUpdateUrl)
                .bodyValue(jobResult)
                .retrieve()
                .bodyToMono(String.class)
                .retryWhen(Retry.backoff(retryAttempts, Duration.ofMillis(retryDelay)));
    }

}
