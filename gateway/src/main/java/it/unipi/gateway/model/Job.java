package it.unipi.gateway.model;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.annotation.JsonInclude;
import io.swagger.v3.oas.annotations.media.Schema;
import it.unipi.gateway.helpers.HashMapConverter;
import it.unipi.gateway.helpers.StringMapConverter;
import jakarta.persistence.*;
import lombok.*;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.io.Serial;
import java.io.Serializable;
import java.time.LocalDateTime;
import java.util.Map;

@Data
@Entity
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Table(name = "jobs", indexes = {
        @Index(name = "idx_job_status", columnList = "status"),
        @Index(name = "idx_job_type", columnList = "type"),
        @Index(name = "idx_job_priority", columnList = "priority"),
        @Index(name = "idx_job_created", columnList = "createdAt"),
        @Index(name = "idx_job_worker", columnList = "workerId")
})
@EntityListeners(AuditingEntityListener.class)
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(description = "Job entity representing a task in the distributed system")
public class Job implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(length = 36)
    @Schema(description = "Unique job identifier", example = "550e8400-e29b-41d4-a716-446655440000")
    private String id;

    @Column(nullable = false)
    @Schema(description = "Type of job to execute", example = "calculate", requiredMode = Schema.RequiredMode.REQUIRED)
    private String type;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Schema(description = "Job priority level", example = "HIGH", requiredMode = Schema.RequiredMode.REQUIRED)
    private JobPriority priority;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Schema(description = "Current job status", example = "PENDING", requiredMode = Schema.RequiredMode.REQUIRED)
    private JobStatus status;

    @Column(name = "worker_id")
    @Schema(description = "ID of worker assigned to this job", example = "worker-python-001")
    private String workerId;

    @Column(columnDefinition = "TEXT")
    @Convert(converter = HashMapConverter.class)
    @Schema(description = "Job payload data as JSON")
    private Map<String, Object> payload;

    @Column(columnDefinition = "TEXT")
    @Convert(converter = HashMapConverter.class)
    @Schema(description = "Job execution result as JSON")
    private Map<String, Object> result;

    @Column(name = "error_message", length = 1000)
    @Schema(description = "Error message if job failed")
    private String errorMessage;

    @Column(name = "retry_count")
    @Builder.Default
    @Schema(description = "Number of retry attempts", example = "0")
    private int retryCount = 0;

    @Column(name = "max_retries")
    @Builder.Default
    @Schema(description = "Maximum retry attempts", example = "3")
    private int maxRetries = 3;

    @Column(name = "execution_timeout")
    @Builder.Default
    @Schema(description = "Execution timeout in seconds", example = "300")
    private int executionTimeout = 300;

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Schema(description = "Job creation timestamp")
    private LocalDateTime createdAt;

    @Column(name = "started_at")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Schema(description = "Job execution start timestamp")
    private LocalDateTime startedAt;

    @Column(name = "completed_at")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Schema(description = "Job completion timestamp")
    private LocalDateTime completedAt;

    @LastModifiedDate
    @Column(name = "updated_at")
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    @Schema(description = "Last update timestamp")
    private LocalDateTime updatedAt;

    @Column(columnDefinition = "TEXT")
    @Convert(converter = StringMapConverter.class)
    @Schema(description = "Job metadata as key-value pairs")
    private Map<String, String> metadata;

    @Column(name = "parent_job_id")
    @Schema(description = "Parent job ID for dependent jobs")
    private String parentJobId;

    @Column(name = "callback_url")
    @Schema(description = "Callback URL for job completion notifications")
    private String callbackUrl;

    @Column(name = "callback_sent")
    @Builder.Default
    @Schema(description = "Indicates if the webhook callback was successfully sent")
    private boolean callbackSent = false;

    @Column(name = "tags", length = 500)
    @Schema(description = "Comma-separated job tags")
    private String tags;

    @Column(name = "queue_name")
    @Schema(description = "RabbitMQ queue name")
    private String queueName;

    @Column(name = "processing_node")
    @Schema(description = "Erlang node processing this job")
    private String processingNode;

    @Column(name = "version")
    @Version
    private Long version;


    public boolean isCompleted() {
        return status == JobStatus.COMPLETED;
    }

    public boolean isFailed() {
        return status == JobStatus.FAILED || status == JobStatus.TIMEOUT;
    }

    public boolean isActive() {
        return status == JobStatus.PENDING ||
                status == JobStatus.QUEUED ||
                status == JobStatus.ASSIGNED ||
                status == JobStatus.RUNNING ||
                status == JobStatus.RETRYING;
    }

    public boolean canRetry() {
        return status == JobStatus.FAILED &&
                retryCount < maxRetries;
    }

    public long getDuration() {
        if (startedAt == null || completedAt == null) {
            return 0;
        }
        return java.time.Duration.between(startedAt, completedAt).toMillis();
    }

    public long getQueueTime() {
        if (createdAt == null || startedAt == null) {
            return 0;
        }
        return java.time.Duration.between(createdAt, startedAt).toMillis();
    }

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) {
            createdAt = LocalDateTime.now();
        }
        if (status == null) {
            status = JobStatus.PENDING;
        }
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now();
    }

}
