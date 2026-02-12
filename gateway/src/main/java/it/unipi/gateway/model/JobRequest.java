package it.unipi.gateway.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.*;

import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(description = "Request object for submitting a new job")
public class JobRequest {

    @NotBlank(message = "Job type is required")
    @Schema(description = "Type of job to execute", example = "calculate")
    private String type;

    @NotNull(message = "Priority is required")
    @Schema(description = "Priority of the job", example = "HIGH")
    private JobPriority jobPriority;

    @Schema(description = "Job payload data", example = "{\"numbers\": [1, 2, 3, 4, 5]}")
    private Map<String, Object> payload;

    @Schema(description = "Maximum number of retries on failure", example = "3")
    @Builder.Default
    @Positive(message = "Maximum retries must be positive")
    private int maxRetries = 3;

    @Positive(message = "Execution timeout must be positive")
    @Schema(description = "Execution timeout in seconds", example = "300")
    @Builder.Default
    private int executionTimeout = 300; // 5 minutes default

    @Schema(description = "Metadata for the job", example = "{\"userId\": \"123\", \"source\": \"web\"}")
    private Map<String, String> metadata;

    @Schema(description = "Parent job ID for job dependencies", example = "job-12345")
    private String parentJobId;

    @Schema(description = "Schedule job for future execution (ISO 8601 format)", example = "2024-12-01T10:00:00Z")
    private String scheduleAt;

    @Schema(description = "Callback URL for job completion notifications")
    private String callbackUrl;

    @Schema(description = "Job tags for categorization", example = "[\"urgent\", \"report\", \"user-123\"]")
    private String[] tags;

    public void validate() {
        if (maxRetries < 0) {
            throw new IllegalArgumentException("maxRetries cannot be negative");
        }
        if (executionTimeout <= 0) {
            throw new IllegalArgumentException("executionTimeout must be positive");
        }
        if (jobPriority == null) {
            throw new IllegalArgumentException("priority is required");
        }
    }

}
