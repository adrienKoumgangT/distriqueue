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
public class Job {

    private String id;
    private String type;
    private Integer priority;
    private String status;
    private String workerId;
    private Map<String, Object> payload;
    private Map<String, Object> result;
    private String errorMessage;
    private Integer retryCount;
    private Integer maxRetries;
    private Integer executionTimeout;
    private LocalDateTime createdAt;
    private LocalDateTime startedAt;
    private LocalDateTime completedAt;
    private Map<String, String> metadata;
    private String parentJobId;
    private String callbackUrl;

    // Job types
    public static class Types {
        public static final String CALCULATE = "calculate";
        public static final String TRANSFORM = "transform";
        public static final String VALIDATE = "validate";
        public static final String SORT = "sort";
        public static final String FILTER = "filter";
        public static final String AGGREGATE = "aggregate";
    }

    // Statuses
    public static class Statuses {
        public static final String PENDING = "pending";
        public static final String RUNNING = "running";
        public static final String COMPLETED = "completed";
        public static final String FAILED = "failed";
        public static final String CANCELLED = "cancelled";
    }

    // Helper methods
    public boolean isHighPriority() {
        return priority != null && priority >= 10;
    }

    public boolean isMediumPriority() {
        return priority != null && priority >= 5 && priority < 10;
    }

    public boolean isLowPriority() {
        return priority != null && priority < 5;
    }

    public boolean canRetry() {
        return Statuses.FAILED.equals(status) &&
                retryCount != null && maxRetries != null &&
                retryCount < maxRetries;
    }

}
