package it.unipi.javaworker.consumer;

import com.google.gson.Gson;
import com.rabbitmq.client.Channel;
import com.rabbitmq.client.GetResponse;
import it.unipi.javaworker.handler.JobHandler;
import it.unipi.javaworker.model.Job;
import it.unipi.javaworker.model.JobResult;
import it.unipi.javaworker.model.WorkerMetrics;
import it.unipi.javaworker.service.StatusUpdateService;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.rabbit.connection.Connection;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.Executor;
import java.util.concurrent.Semaphore;

@Slf4j
@Component
@RequiredArgsConstructor
public class JobConsumer {

    private final List<JobHandler> jobHandlers;
    private final WorkerMetrics workerMetrics;
    private final StatusUpdateService statusUpdateService;
    private final ConnectionFactory connectionFactory;
    private final Gson gson = new Gson();

    @Qualifier("jobProcessingExecutor")
    private final Executor jobProcessingExecutor;

    @Value("${distriqueue.worker.capacity:10}")
    private int capacity;

    @Value("${distriqueue.worker.queues:job.high,job.medium,job.low}")
    private String[] queues;

    private Semaphore capacitySemaphore;
    private volatile boolean running = true;
    private Thread pollingThread;

    @PostConstruct
    public void init() {
        log.info("JobConsumer initialized with {} handlers", jobHandlers.size());
        jobHandlers.forEach(handler -> log.info("Registered handler: {}", handler.getName()));

        // Initialize the semaphore with our exact capacity limit
        capacitySemaphore = new Semaphore(capacity);

        // Start the strict priority polling loop in a background thread
        pollingThread = new Thread(this::priorityPollingLoop, "priority-polling-thread");
        pollingThread.start();
    }

    @PreDestroy
    public void shutdown() {
        log.info("Shutting down Priority Polling Loop...");
        running = false;
        if (pollingThread != null) {
            pollingThread.interrupt();
        }
    }

    /**
     * This loop strictly enforces High -> Medium -> Low priority
     * and completely stops fetching messages when capacity is reached.
     */
    private void priorityPollingLoop() {
        // Use Spring's ConnectionFactory to get a raw RabbitMQ Channel
        try (Connection connection = connectionFactory.createConnection();
             Channel channel = connection.createChannel(false)) {

            channel.basicQos(capacity); // Prefetch up to our capacity limit
            log.info("Started strict priority polling on queues: {}", (Object) queues);

            while (running) {
                try {
                    // 1. Wait here until we have a free execution slot!
                    capacitySemaphore.acquire();

                    boolean messageFound = false;

                    // 2. Check queues strictly from top to bottom (High -> Med -> Low)
                    for (String queue : queues) {
                        GetResponse response = channel.basicGet(queue, false);

                        if (response != null) {
                            messageFound = true;
                            log.debug("Pulled message from priority queue: {}", queue);

                            // 3. Offload to the ThreadPool so the loop can fetch the next message!
                            jobProcessingExecutor.execute(() -> processAndAckJob(channel, response));

                            // Break out of the for-loop so we check High priority again!
                            break;
                        }
                    }

                    if (!messageFound) {
                        // If all queues are empty, return the ticket and wait a fraction of a second
                        capacitySemaphore.release();
                        Thread.sleep(100);
                    }

                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    break;
                } catch (Exception e) {
                    log.error("Error in polling loop: {}", e.getMessage());
                    capacitySemaphore.release();
                    Thread.sleep(1000); // Backoff on error
                }
            }
        } catch (Exception e) {
            log.error("RabbitMQ connection error in polling thread", e);
        }
    }

    /**
     * Executes the job synchronously inside the background thread, then safely acks.
     */
    private void processAndAckJob(Channel channel, GetResponse response) {
        long deliveryTag = response.getEnvelope().getDeliveryTag();
        Job job = null;

        try {
            // Parse JSON manually since we aren't using @RabbitListener
            String jsonBody = new String(response.getBody(), StandardCharsets.UTF_8);
            job = gson.fromJson(jsonBody, Job.class);
            String jobId = job.getId();

            workerMetrics.incrementJobsProcessed();
            workerMetrics.setCurrentLoad(workerMetrics.getCurrentLoad().incrementAndGet());

            log.info("[{}] Received job of type: {}", jobId, job.getType());

            Job finalJob = job;
            Optional<JobHandler> handlerOpt = jobHandlers.stream()
                    .filter(h -> h.canHandle(finalJob.getType()))
                    .findFirst();

            if (handlerOpt.isEmpty()) {
                log.error("[{}] No handler found for job type: {}", jobId, job.getType());
                rejectJob(channel, deliveryTag, jobId, "No handler");
                return;
            }

            job.setWorkerId(workerMetrics.getWorkerId());
            statusUpdateService.sendStatusUpdate(JobResult.progress(jobId, workerMetrics.getWorkerId(), 0));

            JobHandler handler = handlerOpt.get();
            Instant startTime = Instant.now();
            log.debug("[{}] Processing with handler: {}", jobId, handler.getName());

            // Since handler.handle() returns a CompletableFuture, we wait for it here
            JobResult result = handler.handle(job).get();

            long processingTime = Duration.between(startTime, Instant.now()).toMillis();
            workerMetrics.addProcessingTime(processingTime);

            if (Job.Statuses.COMPLETED.equals(result.getStatus())) {
                workerMetrics.incrementJobsSucceeded();
                log.info("[{}] Job completed successfully in {}ms", jobId, processingTime);
                statusUpdateService.sendStatusUpdate(result);
                acknowledgeJob(channel, deliveryTag, jobId);
            } else {
                workerMetrics.incrementJobsFailed();
                statusUpdateService.sendStatusUpdate(result);
                handleFailure(job, channel, deliveryTag, jobId);
            }

        } catch (Exception e) {
            workerMetrics.incrementJobsFailed();
            String jobId = (job != null) ? job.getId() : "unknown";
            log.error("[{}] Job processing failed: {}", jobId, e.getMessage(), e);

            statusUpdateService.sendStatusUpdate(
                    JobResult.failure(jobId, workerMetrics.getWorkerId(), "Processing error: " + e.getMessage())
            );
            handleFailure(job, channel, deliveryTag, jobId);
        } finally {
            workerMetrics.setCurrentLoad(workerMetrics.getCurrentLoad().decrementAndGet());

            // Release the ticket so the polling loop can grab another job!
            capacitySemaphore.release();
        }
    }

    private void handleFailure(Job job, Channel channel, long deliveryTag, String jobId) {
        if (job != null && job.canRetry()) {
            rejectJobForRetry(channel, deliveryTag, jobId);
        } else {
            rejectJobPermanently(channel, deliveryTag, jobId);
        }
    }

    private void acknowledgeJob(Channel channel, long deliveryTag, String jobId) {
        try {
            // RabbitMQ Java Client allows basicAck from any thread!
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
