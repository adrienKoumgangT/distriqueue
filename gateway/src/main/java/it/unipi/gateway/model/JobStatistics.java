package it.unipi.gateway.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.*;

import java.time.LocalDateTime;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(description = "Job execution statistics")
public class JobStatistics {

    @Schema(description = "Total number of jobs")
    private long totalJobs;

    @Schema(description = "Number of pending jobs")
    private long pendingJobs;

    @Schema(description = "Number of running jobs")
    private long runningJobs;

    @Schema(description = "Number of completed jobs")
    private long completedJobs;

    @Schema(description = "Number of failed jobs")
    private long failedJobs;

    @Schema(description = "Success rate percentage", example = "95.5")
    private double successRate;

    @Schema(description = "Average queue time in milliseconds")
    private double averageQueueTimeMs;

    @Schema(description = "Average execution time in milliseconds")
    private double averageExecutionTimeMs;

    @Schema(description = "Jobs by type")
    private Map<String, Long> jobsByType;

    @Schema(description = "Jobs by priority")
    private Map<JobPriority, Long> jobsByPriority;

    @Schema(description = "Jobs by worker")
    private Map<String, Long> jobsByWorker;

    @Schema(description = "Hourly job throughput")
    private Map<String, Long> hourlyThroughput;

    @Schema(description = "Time range start")
    private LocalDateTime timeRangeStart;

    @Schema(description = "Time range end")
    private LocalDateTime timeRangeEnd;

    public void calculateSuccessRate() {
        if (totalJobs == 0) {
            this.successRate = 0.0;
        } else {
            this.successRate = (double) completedJobs / totalJobs * 100;
        }
    }

}
