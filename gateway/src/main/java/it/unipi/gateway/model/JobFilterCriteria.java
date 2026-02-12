package it.unipi.gateway.model;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.*;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "Criteria for filtering jobs")
public class JobFilterCriteria {

    @Schema(description = "Filter by job type", example = "calculate")
    private String type;

    @Schema(description = "Filter by priority", example = "HIGH")
    private JobPriority jobPriority;

    @Schema(description = "Filter by status", example = "COMPLETED")
    private JobStatus jobStatus;

    @Schema(description = "Filter by worker ID", example = "worker-python-001")
    private String workerId;

    @Schema(description = "Filter by creation date from (ISO 8601)", example = "2024-01-01T00:00:00Z")
    private LocalDateTime createdFrom;

    @Schema(description = "Filter by creation date to (ISO 8601)", example = "2024-01-31T23:59:59Z")
    private LocalDateTime createdTo;

    @Schema(description = "Page number (0-based)", example = "0")
    @Builder.Default
    private int page = 0;

    @Schema(description = "Page size", example = "20")
    @Builder.Default
    private int size = 20;

    @Schema(description = "Sort field", example = "createdAt")
    private String sortBy;

    @Schema(description = "Sort direction", example = "DESC")
    private String sortDirection;

    public void validate() {
        if (page < 0) {
            throw new IllegalArgumentException("Page cannot be negative");
        }
        if (size <= 0 || size > 100) {
            throw new IllegalArgumentException("Size must be between 1 and 100");
        }
        if (createdFrom != null && createdTo != null && createdFrom.isAfter(createdTo)) {
            throw new IllegalArgumentException("createdFrom cannot be after createdTo");
        }
    }

}
