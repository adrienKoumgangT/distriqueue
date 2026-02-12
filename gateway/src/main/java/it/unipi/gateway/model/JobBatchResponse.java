package it.unipi.gateway.model;

import io.swagger.v3.oas.annotations.media.Schema;
import lombok.*;

import java.util.List;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "Response for batch job submission")
public class JobBatchResponse {

    @Schema(description = "Batch ID", example = "batch-12345")
    private String batchId;

    @Schema(description = "Total jobs submitted")
    private int totalJobs;

    @Schema(description = "Successfully submitted jobs")
    private int successful;

    @Schema(description = "Failed job submissions")
    private int failed;

    @Schema(description = "List of submitted job IDs")
    private List<String> jobIds;

    @Schema(description = "Error details for failed submissions")
    private Map<String, String> errors;

    @Schema(description = "Batch submission timestamp")
    private String submittedAt;

    @Schema(description = "Estimated completion time")
    private String estimatedCompletion;

}
