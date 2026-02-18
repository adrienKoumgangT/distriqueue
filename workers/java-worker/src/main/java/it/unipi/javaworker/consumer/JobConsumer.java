package it.unipi.javaworker.consumer;

import com.rabbitmq.client.Channel;
import it.unipi.javaworker.handler.JobHandler;
import it.unipi.javaworker.model.Job;
import it.unipi.javaworker.model.JobResult;
import it.unipi.javaworker.model.WorkerMetrics;
import it.unipi.javaworker.service.StatusUpdateService;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.retry.annotation.Backoff;
import org.springframework.retry.annotation.Retryable;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;

@Slf4j
@Component
@RequiredArgsConstructor
public class JobConsumer {

    private final List<JobHandler> jobHandlers;

    private final WorkerMetrics workerMetrics;

    private final StatusUpdateService statusUpdateService;

    private final RabbitTemplate rabbitTemplate;

    @Qualifier("jobProcessingExecutor")
    private final Executor jobProcessingExecutor;

    @PostConstruct
    public void init() {
        log.info("JobConsumer initialized with {} handlers", jobHandlers.size());
        jobHandlers.forEach(handler -> log.info("Registered handler: {}", handler.getName()));
    }

    @RabbitListener(
            queues = "#{'${distriqueue.worker.queues:job.high,job.medium,job.low}'.split(',')}",
            containerFactory = "rabbitListenerContainerFactory"
    )
    @Retryable(
            retryFor = {Exception.class},
            maxAttempts = 3,
            backoff = @Backoff(delay = 1000, multiplier = 2.0, maxDelay = 10000)
    )
    public void consumeJob(Job job, Message message, Channel channel) {
        String jobId = job.getId();
        long deliveryTag = message.getMessageProperties().getDeliveryTag();

        log.info(
                "[{}] Received job of type: {}, priority: {}",
                jobId,
                job.getType(),
                job.getPriority()
        );

        workerMetrics.incrementJobsProcessed();
        workerMetrics.setCurrentLoad(workerMetrics.getCurrentLoad().incrementAndGet());

        try {
            Optional<JobHandler> handler = jobHandlers.stream()
                    .filter(h -> h.canHandle(job.getType()))
                    .findFirst();

            if (handler.isEmpty()) {
                log.error("[{}] No handler found for job type: {}", jobId, job.getType());
                rejectJob(channel, deliveryTag, jobId, "No handler for job type: " + job.getType());
                return;
            }

            job.setWorkerId(workerMetrics.getWorkerId());

            statusUpdateService.sendStatusUpdate(
                    JobResult.progress(jobId, workerMetrics.getWorkerId(), 0)
            );

            processJobAsync(job, handler.get(), channel, deliveryTag);

        } catch (Exception e) {
            log.error("[{}] Error processing job: {}", jobId, e.getMessage(), e);
            rejectJob(channel, deliveryTag, jobId, "Processing error: " + e.getMessage());
        }
    }

    @Async("jobProcessingExecutor")
    public void processJobAsync(
            Job job,
            JobHandler handler,
            Channel channel,
            long deliveryTag
    ) {
        String jobId = job.getId();
        Instant startTime = Instant.now();

        try {
            log.debug("[{}] Processing with handler: {}", jobId, handler.getName());

            CompletableFuture<JobResult> future = handler.handle(job);

            JobResult result = future.get();

            Instant endTime = Instant.now();
            long processingTime = Duration.between(startTime, endTime).toMillis();

            workerMetrics.addProcessingTime(processingTime);

            if (Job.Statuses.COMPLETED.equals(result.getStatus())) {
                workerMetrics.incrementJobsSucceeded();
                log.info("[{}] Job completed successfully in {}ms", jobId, processingTime);

                statusUpdateService.sendStatusUpdate(result);

                acknowledgeJob(channel, deliveryTag, jobId);

            } else {
                workerMetrics.incrementJobsFailed();
                log.error("[{}] Job failed: {}", jobId, result.getErrorMessage());

                statusUpdateService.sendStatusUpdate(result);

                if (job.canRetry()) {
                    log.info("[{}] Job can be retried, rejecting for requeue", jobId);
                    rejectJobForRetry(channel, deliveryTag, jobId);
                } else {
                    log.info("[{}] Job retries exhausted, rejecting permanently", jobId);
                    rejectJobPermanently(channel, deliveryTag, jobId);
                }
            }

        } catch (Exception e) {
            workerMetrics.incrementJobsFailed();
            log.error("[{}] Job processing failed: {}", jobId, e.getMessage(), e);

            statusUpdateService.sendStatusUpdate(
                    JobResult.failure(
                            jobId,
                            workerMetrics.getWorkerId(),
                            "Processing error: " + e.getMessage()
                    )
            );

            if (job.canRetry()) {
                rejectJobForRetry(channel, deliveryTag, jobId);
            } else {
                rejectJobPermanently(channel, deliveryTag, jobId);
            }

        } finally {
            workerMetrics.setCurrentLoad(workerMetrics.getCurrentLoad().decrementAndGet());
        }
    }

    private void acknowledgeJob(Channel channel, long deliveryTag, String jobId) {
        try {
            channel.basicAck(deliveryTag, false);
            log.debug("[{}] Message acknowledged", jobId);
        } catch (IOException e) {
            log.error("[{}] Failed to acknowledge message: {}", jobId, e.getMessage());
        }
    }

    private void rejectJob(Channel channel, long deliveryTag, String jobId, String reason) {
        try {
            channel.basicReject(deliveryTag, false); // Don't requeue
            log.warn("[{}] Job rejected: {}", jobId, reason);
        } catch (IOException e) {
            log.error("[{}] Failed to reject message: {}", jobId, e.getMessage());
        }
    }

    private void rejectJobForRetry(Channel channel, long deliveryTag, String jobId) {
        try {
            channel.basicReject(deliveryTag, true); // Requeue for retry
            log.info("[{}] Job rejected for retry", jobId);
        } catch (IOException e) {
            log.error("[{}] Failed to reject message for retry: {}", jobId, e.getMessage());
        }
    }

    private void rejectJobPermanently(Channel channel, long deliveryTag, String jobId) {
        try {
            channel.basicReject(deliveryTag, false); // Don't requeue (goes to DLQ)
            log.info("[{}] Job rejected permanently", jobId);
        } catch (IOException e) {
            log.error("[{}] Failed to reject message permanently: {}", jobId, e.getMessage());
        }
    }

}
