package it.unipi.gateway.repository;

import it.unipi.gateway.model.Job;
import it.unipi.gateway.model.JobPriority;
import it.unipi.gateway.model.JobStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface JobRepository extends JpaRepository<Job, String> {

    // Basic CRUD operations provided by JpaRepository

    /// Find by ID and Status
    Optional<Job> findByIdAndStatus(String id, JobStatus jobStatus);

    /// Find by Status
    List<Job> findByStatus(JobStatus jobStatus);

    /// Find by Status with Pagination
    Page<Job> findByStatus(JobStatus jobStatus, Pageable pageable);

    /// Find by Type and Status
    List<Job> findByTypeAndStatus(String type, JobStatus jobStatus);

    /// Find by Priority and Status
    List<Job> findByPriorityAndStatus(JobPriority jobPriority, JobStatus jobStatus);

    /// Find by Worker ID and Status
    List<Job> findByWorkerIdAndStatus(String workerId, JobStatus jobStatus);

    /// Find by Worker ID
    List<Job> findByWorkerId(String workerId);

    /// Find by Parent Job ID
    List<Job> findByParentJobId(String parentJobId);

    /// Find by Created At Before (Requested method)
    List<Job> findByCreatedAtBefore(LocalDateTime dateTime);

    /// Find by Created At After
    List<Job> findByCreatedAtAfter(LocalDateTime dateTime);

    /// Find by Created At Between
    List<Job> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);

    /// Find by Started At Before
    List<Job> findByStartedAtBefore(LocalDateTime dateTime);

    /// Find by Completed At Before
    List<Job> findByCompletedAtBefore(LocalDateTime dateTime);

    /// Find by Updated At Before
    List<Job> findByUpdatedAtBefore(LocalDateTime dateTime);

    /// Find jobs that are older than specified date and have specific status
    List<Job> findByCreatedAtBeforeAndStatus(LocalDateTime dateTime, JobStatus jobStatus);

    /// Find jobs with no worker assigned
    List<Job> findByWorkerIdIsNull();

    /// Find jobs with no worker assigned and specific status
    List<Job> findByWorkerIdIsNullAndStatus(JobStatus jobStatus);

    /// Find jobs that have exceeded their timeout (started but not completed)
    @Query("SELECT j FROM Job j WHERE j.status = 'RUNNING' AND j.startedAt < :timeoutThreshold")
    List<Job> findStuckJobs(@Param("timeoutThreshold") LocalDateTime timeoutThreshold);

    /// Find jobs that are ready for retry (FAILED status, retryCount < maxRetries)
    @Query("SELECT j FROM Job j WHERE j.status = 'FAILED' AND j.retryCount < j.maxRetries")
    List<Job> findJobsReadyForRetry();

    /// Find jobs by priority range
    @Query("SELECT j FROM Job j WHERE j.priority IN :priorities")
    List<Job> findByPriorityIn(@Param("priorities") List<JobPriority> priorities);

    /// Find jobs by multiple statuses
    @Query("SELECT j FROM Job j WHERE j.status IN :statuses")
    List<Job> findByStatusIn(@Param("statuses") List<JobStatus> jobStatuses);

    @Query("""
            SELECT j
            FROM Job j
            WHERE (:type IS NULL OR j.type = :type)
                AND (:priority IS NULL OR j.priority = :priority)
                AND (:status IS NULL OR j.status = :status)
                AND (cast(:createdFrom as timestamp) IS NULL OR j.createdAt >= :createdFrom)
                AND (cast(:createdTo as timestamp) IS NULL OR j.createdAt <= :createdTo)
            """)
    Page<Job> findWithFilters(
            @Param("type") String type,
            @Param("priority") JobPriority jobPriority,
            @Param("status") JobStatus jobStatus,
            @Param("createdFrom") LocalDateTime createdFrom,
            @Param("createdTo") LocalDateTime createdTo,
            Pageable pageable);

    /// Advanced filtering with pagination
    @Query("""
           SELECT j
           FROM Job j
           WHERE (:type IS NULL OR j.type = :type)
           AND (:priority IS NULL OR j.priority = :priority)
           AND (:status IS NULL OR j.status = :status)
           AND (:workerId IS NULL OR j.workerId = :workerId)
           AND (cast(:createdFrom as timestamp) IS NULL OR j.createdAt >= :createdFrom)
           AND (cast(:createdTo as timestamp) IS NULL OR j.createdAt <= :createdTo)
           AND (cast(:startedFrom as timestamp) IS NULL OR j.startedAt >= :startedFrom)
           AND (cast(:startedTo as timestamp) IS NULL OR j.startedAt <= :startedTo)
           AND (cast(:completedFrom as timestamp) IS NULL OR j.completedAt >= :completedFrom)
           AND (cast(:completedTo as timestamp) IS NULL OR j.completedAt <= :completedTo)
           """)
    Page<Job> findWithAdvancedFilters(
            @Param("type") String type,
            @Param("priority") JobPriority jobPriority,
            @Param("status") JobStatus jobStatus,
            @Param("workerId") String workerId,
            @Param("createdFrom") LocalDateTime createdFrom,
            @Param("createdTo") LocalDateTime createdTo,
            @Param("startedFrom") LocalDateTime startedFrom,
            @Param("startedTo") LocalDateTime startedTo,
            @Param("completedFrom") LocalDateTime completedFrom,
            @Param("completedTo") LocalDateTime completedTo,
            Pageable pageable);

    // Count operations
    long countByStatus(JobStatus jobStatus);

    long countByTypeAndStatus(String type, JobStatus jobStatus);

    long countByPriorityAndStatus(JobPriority jobPriority, JobStatus jobStatus);

    long countByWorkerIdAndStatus(String workerId, JobStatus jobStatus);

    long countByCreatedAtBetween(LocalDateTime start, LocalDateTime end);

    // Statistics queries
    @Query("SELECT j.type, COUNT(j) FROM Job j GROUP BY j.type ORDER BY COUNT(j) DESC")
    List<Object[]> countJobsByType();

    @Query("SELECT j.priority, COUNT(j) FROM Job j GROUP BY j.priority")
    List<Object[]> countJobsByPriority();

    @Query("SELECT j.status, COUNT(j) FROM Job j GROUP BY j.status")
    List<Object[]> countJobsByStatus();

    @Query("""
            SELECT j.workerId, COUNT(j)
            FROM Job j
            WHERE j.workerId IS NOT NULL
            GROUP BY j.workerId
            """)
    List<Object[]> countJobsByWorker();

    /// Average execution time
    @Query(value ="""
            SELECT AVG(TIMESTAMPDIFF(MILLISECOND, j.started_at, j.completed_at))
            FROM jobs j
            WHERE j.status = 'COMPLETED'
                AND j.started_at IS NOT NULL
                AND j.completed_at IS NOT NULL
            """, nativeQuery = true)
    Double getAverageExecutionTimeMs();

    /// Average queue time
    @Query(value ="""
            SELECT AVG(TIMESTAMPDIFF(MILLISECOND, j.created_at, j.started_at))
            FROM jobs j
            WHERE j.status IN ('COMPLETED', 'FAILED', 'TIMEOUT')
                AND j.created_at IS NOT NULL
                AND j.started_at IS NOT NULL
            """, nativeQuery = true)
    Double getAverageQueueTimeMs();

    /// Success rate by job type
    @Query("""
            SELECT j.type,
            SUM(CASE WHEN j.status = 'COMPLETED' THEN 1 ELSE 0 END) as completed,
            COUNT(j) as total
            FROM Job j
            GROUP BY j.type
            """)
    List<Object[]> getSuccessRateByType();

    @Query("""
            SELECT FUNCTION('HOUR', j.completedAt), COUNT(j)
            FROM Job j
            WHERE j.status = 'COMPLETED'
                AND j.completedAt IS NOT NULL
            GROUP BY FUNCTION('HOUR', j.completedAt)
            ORDER BY FUNCTION('HOUR', j.completedAt)
            """)
    List<Object[]> getHourlyThroughput();

    /// Find jobs with specific tags (using LIKE for comma-separated tags)
    @Query("""
            SELECT j
            FROM Job j
            WHERE j.tags LIKE %:tag%
            """)
    List<Job> findByTag(@Param("tag") String tag);

    /// Find jobs by callback URL
    List<Job> findByCallbackUrl(String callbackUrl);

    /// Find jobs without callback URL
    List<Job> findByCallbackUrlIsNull();

    /// Find jobs that need callback (completed/failed with callback URL)
    @Query("""
            SELECT j
            FROM Job j
            WHERE j.callbackUrl IS NOT NULL
                AND j.status IN ('COMPLETED', 'FAILED', 'TIMEOUT')
                AND j.callbackSent = false
            """)
    List<Job> findJobsNeedingCallback();

    /// Custom query to update job status in bulk
    @Query("""
            UPDATE Job j
                SET j.status = :newStatus,
                    j.updatedAt = CURRENT_TIMESTAMP
            WHERE j.id IN :jobIds
            """)
    @org.springframework.data.jpa.repository.Modifying
    @org.springframework.transaction.annotation.Transactional
    int updateJobStatusInBulk(@Param("jobIds") List<String> jobIds,
                              @Param("newStatus") JobStatus newJobStatus);

    /// Find jobs with specific metadata key-value pair
    @Query("""
            SELECT j
            FROM Job j
            WHERE FUNCTION('JSON_EXTRACT', j.metadata, :keyPath) = :value
            """)
    List<Job> findByMetadataKeyValue(@Param("keyPath") String keyPath,
                                     @Param("value") String value);

    /// Find the oldest pending job
    @Query("""
            SELECT j
            FROM Job j
            WHERE j.status = 'PENDING'
            ORDER BY j.createdAt ASC, j.priority DESC
            LIMIT 1
            """)
    Optional<Job> findOldestPendingJob();

}
