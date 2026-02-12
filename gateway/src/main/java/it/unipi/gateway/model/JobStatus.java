package it.unipi.gateway.model;

import lombok.Getter;

@Getter
public enum JobStatus {
    PENDING("Job is waiting in queue"),
    QUEUED("Job is in RabbitMQ queue"),
    ASSIGNED("Job assigned to worker"),
    RUNNING("Job is being executed"),
    COMPLETED("Job completed successfully"),
    FAILED("Job failed"),
    RETRYING("Job is being retried"),
    TIMEOUT("Job timed out"),
    CANCELLED("Job was cancelled"),
    ;

    private final String description;

    JobStatus(String description) {
        this.description = description;
    }

}
