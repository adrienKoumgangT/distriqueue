package it.unipi.javaworker.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.*;

import java.time.LocalDateTime;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
public class JobResult {

    private String jobId;
    private String status;
    private String workerId;
    private Map<String, Object> result;
    private String errorMessage;
    private Integer progress;
    private Long executionTimeMs;
    private Long memoryUsageMb;
    private LocalDateTime completedAt;
    private Map<String, Object> metadata;

    public static JobResult success(String jobId, String workerId, Map<String, Object> result) {
        return JobResult.builder()
                .jobId(jobId)
                .status(Job.Statuses.COMPLETED)
                .workerId(workerId)
                .result(result)
                .completedAt(LocalDateTime.now())
                .build();
    }

    public static JobResult failure(String jobId, String workerId, String errorMessage) {
        return JobResult.builder()
                .jobId(jobId)
                .status(Job.Statuses.FAILED)
                .workerId(workerId)
                .errorMessage(errorMessage)
                .completedAt(LocalDateTime.now())
                .build();
    }

    public static JobResult progress(String jobId, String workerId, int progress) {
        return JobResult.builder()
                .jobId(jobId)
                .status(Job.Statuses.RUNNING)
                .workerId(workerId)
                .progress(progress)
                .build();
    }

}
