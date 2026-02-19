package it.unipi.gateway.service;

import it.unipi.gateway.model.*;
import it.unipi.gateway.repository.JobRepository;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.scheduling.annotation.Async;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
import tools.jackson.databind.json.JsonMapper;

import java.io.IOException;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

@Slf4j
@Service
@Transactional
@RequiredArgsConstructor
public class JobService {

    private final JobRepository jobRepository;

    private final RabbitTemplate rabbitTemplate;

    private final ErlangClient erlangClient;

    private final JsonMapper jsonMapper;


    @Value("${rabbitmq.exchange.jobs:jobs.exchange}")
    private String jobsExchange;

    @Value("${distriqueue.job.default-timeout:300}")
    private int defaultTimeout;

    @Value("${distriqueue.job.default-retries:3}")
    private int defaultRetries;

    @Value("${distriqueue.job.max-batch-size:1000}")
    private int maxBatchSize;

    private final Map<String, SseEmitter> sseEmitters = new ConcurrentHashMap<>();
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2);
    private final ExecutorService asyncExecutor = Executors.newVirtualThreadPerTaskExecutor();

    @PostConstruct
    public void init() {
        // Start monitoring for stuck jobs
        scheduler.scheduleAtFixedRate(this::monitorStuckJobs, 30, 60, TimeUnit.SECONDS);

        // Start cleanup for old completed jobs
        scheduler.scheduleAtFixedRate(this::cleanupOldJobs, 1, 6, TimeUnit.HOURS);

        log.info("JobService initialized with default timeout: {}s, retries: {}",
                defaultTimeout, defaultRetries);
    }

    @PreDestroy
    public void cleanup() {
        scheduler.shutdown();
        asyncExecutor.shutdown();
        sseEmitters.clear();
        log.info("JobService shutdown completed");
    }

    public Job createJob(JobRequest request) {
        log.debug("Creating job from request: {}", request.getType());

        Job job = Job.builder()
                .type(request.getType())
                .priority(request.getJobPriority())
                .status(JobStatus.PENDING)
                .payload(request.getPayload())
                .maxRetries(request.getMaxRetries() > 0 ? request.getMaxRetries() : defaultRetries)
                .executionTimeout(request.getExecutionTimeout() > 0 ?
                        request.getExecutionTimeout() : defaultTimeout)
                .metadata(request.getMetadata())
                .parentJobId(request.getParentJobId())
                .callbackUrl(request.getCallbackUrl())
                .tags(request.getTags() != null ? String.join(",", request.getTags()) : null)
                .createdAt(LocalDateTime.now())
                .build();

        job = jobRepository.save(job);
        log.info("Created job {} with priority {}", job.getId(), job.getPriority());

        return job;
    }

    public Job submitJob(Job job) {
        log.debug("Submitting job {} to queue", job.getId());

        job.setStatus(JobStatus.QUEUED);
        job = jobRepository.save(job);

        Job finalJob = job;
        erlangClient.registerJob(job).subscribe(
                res -> log.debug("Job {} registered with Erlang: {}", finalJob.getId(), res),
                err -> log.error("Failed to register job {} with Erlang: {}", finalJob.getId(), err.getMessage())
        );

        String routingKey = getRoutingKey(job.getPriority());
        rabbitTemplate.convertAndSend(jobsExchange, routingKey, job);

        log.info("Job {} submitted to RabbitMQ exchange: {}, routing key: {}",
                job.getId(), jobsExchange, routingKey);

        sendSseUpdate(job);

        return job;
    }

    @Async
    public CompletableFuture<Job> submitJobAsync(Job job) {
        return CompletableFuture.supplyAsync(() -> submitJob(job), asyncExecutor);
    }

    public JobBatchResponse submitBatch(JobBatchRequest batchRequest) {
        log.info(
                "Processing batch request with {} jobs, sequential: {}",
                batchRequest.getJobs().size(),
                batchRequest.isSequential()
        );

        String batchId = UUID.randomUUID().toString();
        List<String> jobIds = new ArrayList<>();
        Map<String, String> errors = new HashMap<>();
        AtomicInteger successful = new AtomicInteger(0);

        if (batchRequest.getJobs().size() > maxBatchSize) {
            throw new IllegalArgumentException(
                    String.format("Batch size %d exceeds maximum allowed %d",
                            batchRequest.getJobs().size(),
                            maxBatchSize
                    )
            );
        }

        if (batchRequest.isSequential()) {
            // Process sequentially
            processSequentialBatch(batchRequest, batchId, jobIds, errors, successful);
        } else {
            // Process in parallel with optional concurrency limit
            processParallelBatch(batchRequest, batchId, jobIds, errors, successful);
        }

        JobBatchResponse response = JobBatchResponse.builder()
                .batchId(batchId)
                .totalJobs(batchRequest.getJobs().size())
                .successful(successful.get())
                .failed(errors.size())
                .jobIds(jobIds)
                .errors(errors)
                .submittedAt(LocalDateTime.now().toString())
                .estimatedCompletion(estimateCompletionTime(batchRequest))
                .build();

        log.info(
                "Batch {} completed: {}/{} successful",
                batchId,
                successful.get(),
                batchRequest.getJobs().size()
        );

        return response;
    }

    private void processSequentialBatch(
            JobBatchRequest batchRequest,
            String batchId,
            List<String> jobIds,
            Map<String, String> errors,
            AtomicInteger successful
    ) {
        for (int i = 0; i < batchRequest.getJobs().size(); i++) {
            JobRequest jobRequest = batchRequest.getJobs().get(i);
            String jobId = "batch-" + batchId + "-" + i;

            try {
                Job job = createJob(jobRequest);
                submitJob(job);
                jobIds.add(job.getId());
                successful.incrementAndGet();

                // Add batch metadata
                Map<String, String> metadata = job.getMetadata();
                if (metadata == null) metadata = new HashMap<>();
                metadata.put("batchId", batchId);
                metadata.put("batchIndex", String.valueOf(i));
                job.setMetadata(metadata);
                jobRepository.save(job);

            } catch (Exception e) {
                errors.put(jobId, e.getMessage());
                if (batchRequest.isStopOnFailure()) {
                    log.warn(
                            "Batch {} stopped on failure at index {}: {}",
                            batchId,
                            i,
                            e.getMessage()
                    );
                    break;
                }
            }

            if (i < batchRequest.getJobs().size() - 1) {
                try {
                    Thread.sleep(batchRequest.getSequentialDelayMs());
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
    }

    private void processParallelBatch(
            JobBatchRequest batchRequest,
            String batchId,
            List<String> jobIds,
            Map<String, String> errors,
            AtomicInteger successful
    ) {
        int maxConcurrent = batchRequest.getMaxConcurrent() != null ?
                batchRequest.getMaxConcurrent() :
                Math.min(10, batchRequest.getJobs().size());

        ExecutorService executor = Executors.newFixedThreadPool(maxConcurrent);
        List<CompletableFuture<Void>> futures = new ArrayList<>();
        CountDownLatch latch = new CountDownLatch(batchRequest.getJobs().size());

        for (int i = 0; i < batchRequest.getJobs().size(); i++) {
            final int index = i;
            final JobRequest jobRequest = batchRequest.getJobs().get(i);
            final String jobId = "batch-" + batchId + "-" + i;

            CompletableFuture<Void> future = CompletableFuture.runAsync(() -> {
                try {
                    Job job = createJob(jobRequest);
                    submitJob(job);

                    synchronized (jobIds) {
                        jobIds.add(job.getId());
                        successful.incrementAndGet();
                    }

                    // Add batch metadata
                    Map<String, String> metadata = job.getMetadata();
                    if (metadata == null) metadata = new HashMap<>();
                    metadata.put("batchId", batchId);
                    metadata.put("batchIndex", String.valueOf(index));
                    job.setMetadata(metadata);
                    jobRepository.save(job);

                } catch (Exception e) {
                    synchronized (errors) {
                        errors.put(jobId, e.getMessage());
                    }
                } finally {
                    latch.countDown();
                }
            }, executor);

            futures.add(future);
        }

        try {
            latch.await(5, TimeUnit.MINUTES);
            CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        } catch (Exception e) {
            log.error("Error processing parallel batch: {}", e.getMessage());
        } finally {
            executor.shutdown();
        }
    }

    public Optional<Job> getJob(String id) {
        return jobRepository.findById(id);
    }

    public Page<JobResponse> getJobs(JobFilterCriteria criteria) {
        Pageable pageable = createPageable(criteria);

        Page<Job> jobs = jobRepository.findWithFilters(
                criteria.getType(),
                criteria.getJobPriority(),
                criteria.getJobStatus(),
                criteria.getCreatedFrom(),
                criteria.getCreatedTo(),
                pageable
        );

        return jobs.map(JobResponse::fromEntity);
    }

    public Optional<Job> cancelJob(String jobId) {
        return jobRepository.findById(jobId)
                .map(job -> {
                    if (job.isActive()) {
                        job.setStatus(JobStatus.CANCELLED);
                        job.setCompletedAt(LocalDateTime.now());
                        job = jobRepository.save(job);

                        // Notify Erlang orchestrator
                        erlangClient.notifyJobCancelled(jobId);

                        // Send SSE update
                        sendSseUpdate(job);

                        log.info("Job {} cancelled", jobId);
                    }
                    return job;
                });
    }

    public Optional<Job> retryJob(String jobId) {
        return jobRepository.findById(jobId)
                .map(job -> {
                    if (job.canRetry()) {
                        job.setStatus(JobStatus.PENDING);
                        job.setRetryCount(job.getRetryCount() + 1);
                        job.setErrorMessage(null);
                        job = jobRepository.save(job);

                        // Resubmit to queue
                        submitJob(job);

                        log.info(
                                "Job {} retried (attempt {}/{})",
                                jobId,
                                job.getRetryCount(),
                                job.getMaxRetries()
                        );
                    }
                    return job;
                });
    }

    public JobStatistics getStatistics(LocalDateTime from, LocalDateTime to) {
        if (from == null) {
            from = LocalDateTime.now().minusDays(7);
        }
        if (to == null) {
            to = LocalDateTime.now();
        }

        List<Job> jobsInPeriod = jobRepository.findByCreatedAtBetween(from, to);

        long totalJobs = jobsInPeriod.size();
        long pendingJobs = jobsInPeriod.stream()
                .filter(job -> job.getStatus() == JobStatus.PENDING)
                .count();
        long runningJobs = jobsInPeriod.stream()
                .filter(job -> job.getStatus() == JobStatus.RUNNING)
                .count();
        long completedJobs = jobsInPeriod.stream()
                .filter(job -> job.getStatus() == JobStatus.COMPLETED)
                .count();
        long failedJobs = jobsInPeriod.stream()
                .filter(Job::isFailed)
                .count();

        // Calculate averages
        double averageQueueTime = jobsInPeriod.stream()
                .filter(job -> job.getQueueTime() > 0)
                .mapToLong(Job::getQueueTime)
                .average()
                .orElse(0.0);

        double averageExecutionTime = jobsInPeriod.stream()
                .filter(job -> job.getDuration() > 0)
                .mapToLong(Job::getDuration)
                .average()
                .orElse(0.0);

        // Group by type
        Map<String, Long> jobsByType = jobsInPeriod.stream()
                .collect(Collectors.groupingBy(Job::getType, Collectors.counting()));

        // Group by priority
        Map<JobPriority, Long> jobsByPriority = jobsInPeriod.stream()
                .collect(Collectors.groupingBy(Job::getPriority, Collectors.counting()));

        // Group by worker
        Map<String, Long> jobsByWorker = jobsInPeriod.stream()
                .filter(job -> job.getWorkerId() != null)
                .collect(Collectors.groupingBy(Job::getWorkerId, Collectors.counting()));

        JobStatistics statistics = JobStatistics.builder()
                .totalJobs(totalJobs)
                .pendingJobs(pendingJobs)
                .runningJobs(runningJobs)
                .completedJobs(completedJobs)
                .failedJobs(failedJobs)
                .averageQueueTimeMs(averageQueueTime)
                .averageExecutionTimeMs(averageExecutionTime)
                .jobsByType(jobsByType)
                .jobsByPriority(jobsByPriority)
                .jobsByWorker(jobsByWorker)
                .timeRangeStart(from)
                .timeRangeEnd(to)
                .build();

        statistics.calculateSuccessRate();

        return statistics;
    }

    public void updateJobStatus(JobStatusUpdate statusUpdate) {
        statusUpdate.validate();

        jobRepository.findById(statusUpdate.getJobId())
                .ifPresent(job -> {
                    JobStatus oldJobStatus = job.getStatus();
                    job.setStatus(statusUpdate.getJobStatus());
                    job.setWorkerId(statusUpdate.getWorkerId());

                    switch (statusUpdate.getJobStatus()) {
                        case RUNNING:
                            if (job.getStartedAt() == null) {
                                job.setStartedAt(LocalDateTime.now());
                            }
                            break;
                        case COMPLETED:
                        case FAILED:
                        case TIMEOUT:
                            job.setCompletedAt(LocalDateTime.now());
                            job.setResult(statusUpdate.getResult());
                            job.setErrorMessage(statusUpdate.getErrorMessage());
                            break;
                    }

                    job = jobRepository.save(job);

                    log.info(
                            "Job {} status updated from {} to {}",
                            job.getId(),
                            oldJobStatus,
                            job.getStatus()
                    );

                    sendSseUpdate(job);

                    callWebhookIfConfigured(job);
                });
    }

    public SseEmitter createJobStream() {
        String clientId = UUID.randomUUID().toString();
        SseEmitter emitter = new SseEmitter(Long.MAX_VALUE);

        sseEmitters.put(clientId, emitter);

        emitter.onCompletion(() -> sseEmitters.remove(clientId));
        emitter.onTimeout(() -> sseEmitters.remove(clientId));
        emitter.onError((e) -> sseEmitters.remove(clientId));

        try {
            Map<String, Object> initData = new HashMap<>();
            initData.put("clientId", clientId);
            initData.put("message", "Connected to job stream");
            initData.put("timestamp", LocalDateTime.now().toString());

            emitter.send(SseEmitter.event()
                    .name("connected")
                    .data(initData));
        } catch (IOException e) {
            log.error("Error sending initial SSE data: {}", e.getMessage());
        }

        log.info("SSE stream created for client: {}", clientId);
        return emitter;
    }

    private void sendSseUpdate(Job job) {
        sseEmitters.forEach((clientId, emitter) -> {
            try {
                Map<String, Object> update = new HashMap<>();
                update.put("jobId", job.getId());
                update.put("status", job.getStatus().name());
                update.put("timestamp", LocalDateTime.now().toString());
                update.put("workerId", job.getWorkerId());

                emitter.send(SseEmitter.event()
                        .name("job-update")
                        .data(update));
            } catch (IOException e) {
                log.warn("Failed to send SSE update to client {}: {}", clientId, e.getMessage());
                sseEmitters.remove(clientId);
            }
        });
    }

    @Scheduled(fixedDelay = 30000) // Every 30 seconds
    public void monitorStuckJobs() {
        log.debug("Checking for stuck jobs...");

        LocalDateTime timeoutThreshold = LocalDateTime.now().minusMinutes(5);

        List<Job> stuckJobs = jobRepository.findByStatus(JobStatus.RUNNING).stream()
                .filter(job -> job.getStartedAt() != null &&
                        job.getStartedAt().isBefore(timeoutThreshold))
                .toList();

        for (Job job : stuckJobs) {
            log.warn(
                    "Job {} appears to be stuck (running since {}). Marking as timeout.",
                    job.getId(),
                    job.getStartedAt()
            );

            job.setStatus(JobStatus.TIMEOUT);
            job.setCompletedAt(LocalDateTime.now());
            job.setErrorMessage("Job timed out after 5 minutes");
            jobRepository.save(job);

            sendSseUpdate(job);
        }
    }

    @Scheduled(cron = "0 0 2 * * ?") // Daily at 2 AM
    public void cleanupOldJobs() {
        log.info("Starting cleanup of old jobs...");

        LocalDateTime cutoffDate = LocalDateTime.now().minusDays(30);

        List<Job> oldJobs = jobRepository.findByCreatedAtBefore(cutoffDate);

        // Archive or delete old jobs
        long deleted = oldJobs.stream()
                .filter(job -> job.isCompleted() || job.isFailed())
                .peek(job -> {
                    // Archive to external storage if needed
                    archiveJob(job);
                    jobRepository.delete(job);
                })
                .count();

        log.info("Cleanup completed. Removed {} old jobs.", deleted);
    }

    private void archiveJob(Job job) {
        // TODO: Implement job archiving logic
        log.debug("Archiving job {} to external storage", job.getId());
    }

    private void callWebhookIfConfigured(Job job) {
        if (job.getCallbackUrl() != null && !job.getCallbackUrl().isBlank()) {
            asyncExecutor.execute(() -> {
                try {
                    Map<String, Object> callbackData = new HashMap<>();
                    callbackData.put("jobId", job.getId());
                    callbackData.put("status", job.getStatus().name());
                    callbackData.put("result", job.getResult());
                    callbackData.put("error", job.getErrorMessage());
                    callbackData.put("timestamp", LocalDateTime.now().toString());

                    String jsonPayload = jsonMapper.writeValueAsString(callbackData);

                    // use RestTemplate or WebClient
                    log.info("Calling webhook for job {}: {}", job.getId(), job.getCallbackUrl());
                    // webClient.post().uri(job.getCallbackUrl()).bodyValue(callbackData).retrieve();

                } catch (Exception e) {
                    log.error("Failed to call webhook for job {}: {}", job.getId(), e.getMessage());
                }
            });
        }
    }

    private String getRoutingKey(JobPriority jobPriority) {
        return switch (jobPriority) {
            case HIGH -> "job.high";
            case MEDIUM -> "job.medium";
            case LOW -> "job.low";
            case CRITICAL -> "job.critical";
            default -> "job.medium";
        };
    }

    private Pageable createPageable(JobFilterCriteria criteria) {
        Sort.Direction direction = Sort.Direction.fromString(criteria.getSortDirection().toUpperCase());
        Sort sort = Sort.by(direction, criteria.getSortBy());

        return PageRequest.of(criteria.getPage(), criteria.getSize(), sort);
    }

    private String estimateCompletionTime(JobBatchRequest batchRequest) {
        // Simple estimation based on job count and sequential flag
        if (batchRequest.isSequential()) {
            long totalDelay = batchRequest.getSequentialDelayMs() *
                    Math.max(0, batchRequest.getJobs().size() - 1);
            LocalDateTime estimated = LocalDateTime.now()
                    .plus(Duration.ofMillis(totalDelay))
                    .plus(Duration.ofSeconds(30L * batchRequest.getJobs().size())); // 30s per job
            return estimated.toString();
        } else {
            // Parallel execution - estimate based on concurrent limit
            int maxConcurrent = batchRequest.getMaxConcurrent() != null ?
                    batchRequest.getMaxConcurrent() : 10;
            int batches = (int) Math.ceil((double) batchRequest.getJobs().size() / maxConcurrent);
            LocalDateTime estimated = LocalDateTime.now()
                    .plus(Duration.ofMinutes(batches)); // 1 minute per batch
            return estimated.toString();
        }
    }

}
