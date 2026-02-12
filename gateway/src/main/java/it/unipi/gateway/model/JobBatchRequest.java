package it.unipi.gateway.model;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import lombok.*;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "Request for submitting multiple jobs in batch")
public class JobBatchRequest {

    @NotEmpty(message = "Jobs list cannot be empty")
    @Schema(description = "List of jobs to submit")
    @Valid
    @NotNull(message = "Jobs list cannot be null")
    private List<JobRequest> jobs;

    @Schema(description = "If true, process jobs sequentially", example = "false")
    @Builder.Default
    private boolean sequential = false;

    @Schema(description = "Delay between sequential jobs in milliseconds", example = "1000")
    @Builder.Default
    private long sequentialDelayMs = 1000;

    @Schema(description = "Stop batch on first failure", example = "false")
    @Builder.Default
    private boolean stopOnFailure = false;

    @Schema(description = "Batch name for identification")
    private String batchName;

    @Schema(description = "Maximum concurrent jobs for parallel processing")
    private Integer maxConcurrent;

    public void validate() {
        if (jobs == null || jobs.isEmpty()) {
            throw new IllegalArgumentException("Jobs list cannot be empty");
        }
        if (sequentialDelayMs < 0) {
            throw new IllegalArgumentException("sequentialDelayMs cannot be negative");
        }
        if (maxConcurrent != null && maxConcurrent <= 0) {
            throw new IllegalArgumentException("maxConcurrent must be positive");
        }
        if (jobs.size() > 1000) {
            throw new IllegalArgumentException("Batch size cannot exceed 1000 jobs");
        }
    }

}
