package it.unipi.gateway.service;

import it.unipi.gateway.model.Job;
import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
@Primary
@Slf4j
public class ErlangClientAdapter implements ErlangClient {

    @Value("${distriqueue.erlang.mode:http}")
    private String erlangMode;

    private final ErlangRestClient erlangRestClient;
    private final ErlangDirectClient erlangDirectClient;
    private boolean useDirectErlang = true;

    public ErlangClientAdapter(
            ErlangRestClient restClient,
            ErlangDirectClient directClient
    ) {
        this.erlangRestClient = restClient;
        this.erlangDirectClient = directClient;
    }

    @PostConstruct
    public void init() {
        useDirectErlang = "direct".equalsIgnoreCase(erlangMode) &&
                erlangDirectClient.isConnected();

        if (useDirectErlang) {
            log.info("Using DIRECT Erlang communication mode");
        } else {
            log.info("Using HTTP Erlang communication mode");
        }
    }

    @Override
    public Mono<String> registerJob(Job job) {
        if (useDirectErlang) {
            return Mono.fromCallable(() -> {
                String result = erlangDirectClient.registerJob(job);
                return result != null ? result : "fallback";
            }).onErrorResume(e -> {
                log.warn("Direct Erlang failed, falling back to HTTP: {}", e.getMessage());
                useDirectErlang = false;
                return erlangRestClient.registerJob(job);
            });
        } else {
            return erlangRestClient.registerJob(job);
        }
    }

    @Override
    public Mono<String> updateJobStatus(String jobId, String status, String workerId) {
        if (useDirectErlang) {
            return Mono.fromCallable(() -> {
                boolean success = erlangDirectClient.updateJobStatus(jobId, status, workerId);
                return success ? "updated" : "failed";
            }).onErrorResume(e -> {
                log.warn("Direct Erlang failed for status update, falling back to HTTP");
                useDirectErlang = false;
                return erlangRestClient.updateJobStatus(jobId, status, workerId);
            });
        } else {
            return erlangRestClient.updateJobStatus(jobId, status, workerId);
        }
    }

    @Override
    public Mono<Void> notifyJobCancelled(String jobId) {
        if (useDirectErlang) {
            return Mono.fromRunnable(() -> erlangDirectClient.notifyJobCancelled(jobId))
                    .onErrorResume(e -> {
                        log.warn("Direct Erlang failed for cancellation, falling back to HTTP");
                        useDirectErlang = false;
                        return erlangRestClient.notifyJobCancelled(jobId);
                    }).then();
        } else {
            return erlangRestClient.notifyJobCancelled(jobId);
        }
    }

    @Override
    public Mono<String> getClusterStatus() {
        if (useDirectErlang) {
            return Mono.fromCallable(
                    erlangDirectClient::getClusterStatus
            ).onErrorResume(e -> {
                log.warn("Direct Erlang failed for cluster status, falling back to HTTP");
                useDirectErlang = false;
                return erlangRestClient.getClusterStatus();
            });
        } else {
            return erlangRestClient.getClusterStatus();
        }
    }

    @Override
    public boolean isConnected() {
        if (useDirectErlang) {
            return erlangDirectClient.isConnected();
        } else {
            return erlangRestClient != null;
        }
    }

}
