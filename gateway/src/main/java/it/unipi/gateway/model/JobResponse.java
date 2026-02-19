package it.unipi.gateway.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.*;

import java.time.LocalDateTime;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(description = "Response object for job operations")
public class JobResponse {

    @Schema(description = "Job ID", example = "550e8400-e29b-41d4-a716-446655440000")
    private String id;

    @Schema(description = "Job type", example = "calculate")
    private String type;

    @Schema(description = "Job priority", example = "HIGH")
    private JobPriority jobPriority;

    @Schema(description = "Current job status", example = "RUNNING")
    private JobStatus jobStatus;

    @Schema(description = "Worker ID assigned to this job", example = "worker-python-001")
    private String workerId;

    @Schema(description = "Job payload")
    private Map<String, Object> payload;

    @Schema(description = "Job execution result")
    private Map<String, Object> result;

    @Schema(description = "Error message if job failed")
    private String errorMessage;

    @Schema(description = "Current retry count", example = "1")
    private int retryCount;

    @Schema(description = "Maximum retry attempts", example = "3")
    private int maxRetries;

    @Schema(description = "Execution timeout in seconds", example = "300")
    private int executionTimeout;

    @Schema(description = "Job creation timestamp")
    @JsonProperty("created_at")
    private LocalDateTime createdAt;

    @Schema(description = "Job execution start timestamp")
    @JsonProperty("started_at")
    private LocalDateTime startedAt;

    @Schema(description = "Job completion timestamp")
    @JsonProperty("completed_at")
    private LocalDateTime completedAt;

    @Schema(description = "Job metadata")
    private Map<String, String> metadata;

    @Schema(description = "Parent job ID for dependent jobs")
    private String parentJobId;

    @Schema(description = "Indicates if the webhook callback was successfully sent")
    @JsonProperty("callback_sent")
    private boolean callbackSent;

    @Schema(description = "Queue time in milliseconds")
    @JsonProperty("queue_time_ms")
    private Long queueTimeMs;

    @Schema(description = "Execution time in milliseconds")
    @JsonProperty("execution_time_ms")
    private Long executionTimeMs;

    @Schema(description = "Total duration in milliseconds")
    @JsonProperty("total_duration_ms")
    private Long totalDurationMs;

    @Schema(description = "Links for HATEOAS")
    private Map<String, String> links;

    // Static factory method to convert from Job entity
    public static JobResponse fromEntity(Job job) {
        if (job == null) {
            return null;
        }

        return JobResponse.builder()
                .id(job.getId())
                .type(job.getType())
                .jobPriority(job.getPriority())
                .jobStatus(job.getStatus())
                .workerId(job.getWorkerId())
                .payload(job.getPayload())
                .result(job.getResult())
                .errorMessage(job.getErrorMessage())
                .retryCount(job.getRetryCount())
                .maxRetries(job.getMaxRetries())
                .executionTimeout(job.getExecutionTimeout())
                .createdAt(job.getCreatedAt())
                .startedAt(job.getStartedAt())
                .completedAt(job.getCompletedAt())
                .metadata(job.getMetadata())
                .parentJobId(job.getParentJobId())
                .callbackSent(job.isCallbackSent())
                .queueTimeMs(job.getQueueTime())
                .executionTimeMs(job.getDuration())
                .totalDurationMs(calculateTotalDuration(job))
                .build();
    }

    private static Long calculateTotalDuration(Job job) {
        if (job.getCreatedAt() == null || job.getCompletedAt() == null) {
            return null;
        }
        return java.time.Duration.between(job.getCreatedAt(), job.getCompletedAt()).toMillis();
    }

}
