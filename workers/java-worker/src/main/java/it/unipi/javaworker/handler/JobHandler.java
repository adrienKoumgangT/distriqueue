package it.unipi.javaworker.handler;

import it.unipi.javaworker.model.Job;
import it.unipi.javaworker.model.JobResult;

import java.util.concurrent.CompletableFuture;

public interface JobHandler {

    /**
     * Check if this handler can process the given job type
     */
    boolean canHandle(String jobType);

    /**
     * Process the job
     */
    CompletableFuture<JobResult> handle(Job job);

    /**
     * Get handler name for logging
     */
    String getName();

}
