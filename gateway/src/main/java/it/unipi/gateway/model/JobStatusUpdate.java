package it.unipi.gateway.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.*;

import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(description = "Job status update from worker")
public class JobStatusUpdate {

    @NotBlank(message = "Job ID is required")
    @Schema(description = "Job ID", example = "550e8400-e29b-41d4-a716-446655440000")
    private String jobId;

    @NotNull(message = "Status is required")
    @Schema(description = "New job status", example = "COMPLETED")
    private JobStatus jobStatus;

    @NotBlank(message = "Worker ID is required")
    @Schema(description = "Worker ID reporting the status", example = "worker-python-001")
    private String workerId;

    @Schema(description = "Job execution result")
    private Map<String, Object> result;

    @Schema(description = "Error message if job failed")
    private String errorMessage;

    @Schema(description = "Progress percentage (0-100)", example = "75")
    private Integer progress;

    @Schema(description = "Additional status metadata")
    private Map<String, Object> metadata;

    @Schema(description = "Timestamp of status update (ISO 8601)", example = "2024-01-15T10:30:45Z")
    private String timestamp;

    @Schema(description = "Execution time in milliseconds")
    private Long executionTimeMs;

    @Schema(description = "Memory usage in MB")
    private Long memoryUsageMb;

    public void validate() {
        if (jobId == null || jobId.trim().isEmpty()) {
            throw new IllegalArgumentException("jobId is required");
        }
        if (jobStatus == null) {
            throw new IllegalArgumentException("status is required");
        }
        if (workerId == null || workerId.trim().isEmpty()) {
            throw new IllegalArgumentException("workerId is required");
        }
        if (progress != null && (progress < 0 || progress > 100)) {
            throw new IllegalArgumentException("progress must be between 0 and 100");
        }
    }

}
