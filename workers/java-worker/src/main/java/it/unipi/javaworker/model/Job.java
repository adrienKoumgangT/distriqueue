package it.unipi.javaworker.model;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.*;

import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public class Job {

    private String id;
    private String type;
    private Integer priority;
    private String status;

    @JsonProperty("worker_id")
    private String workerId;

    private Map<String, Object> payload;

    // Changed to Object to safely parse the "undefined" string from Erlang
    private Object result;

    @JsonProperty("error_message")
    private String errorMessage;

    @JsonProperty("retry_count")
    private Integer retryCount;

    @JsonProperty("max_retries")
    private Integer maxRetries;

    @JsonProperty("execution_timeout")
    private Integer executionTimeout;

    // Changed to Object to safely handle Erlang timestamps or "undefined"
    @JsonProperty("created_at")
    private Object createdAt;

    @JsonProperty("started_at")
    private Object startedAt;

    @JsonProperty("completed_at")
    private Object completedAt;

    private Map<String, String> metadata;

    @JsonProperty("parent_job_id")
    private String parentJobId;

    @JsonProperty("callback_url")
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

    public boolean isHighPriority() { return priority != null && priority >= 10; }
    public boolean isMediumPriority() { return priority != null && priority >= 5 && priority < 10; }
    public boolean isLowPriority() { return priority != null && priority < 5; }

    public boolean canRetry() {
        return Statuses.FAILED.equals(status) &&
                retryCount != null && maxRetries != null &&
                retryCount < maxRetries;
    }

}
