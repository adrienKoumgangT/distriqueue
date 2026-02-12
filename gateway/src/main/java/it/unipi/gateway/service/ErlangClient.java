package it.unipi.gateway.service;

import it.unipi.gateway.model.Job;
import reactor.core.publisher.Mono;

public interface ErlangClient {

    /**
     * Register a job with the Erlang orchestrator
     */
    Mono<String> registerJob(Job job);

    /**
     * Update job status
     */
    Mono<String> updateJobStatus(String jobId, String status, String workerId);

    /**
     * Notify job cancellation
     */
    Mono<Void> notifyJobCancelled(String jobId);

    /**
     * Get cluster status
     */
    Mono<String> getClusterStatus();

    /**
     * Check if client is connected
     */
    boolean isConnected();

}
