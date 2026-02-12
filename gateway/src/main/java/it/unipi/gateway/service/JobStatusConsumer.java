package it.unipi.gateway.service;

import it.unipi.gateway.model.JobStatusUpdate;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;

@Slf4j
@Service
@RequiredArgsConstructor
public class JobStatusConsumer {

    private final JobService jobService;

    private final RabbitTemplate rabbitTemplate;


    @Value("${rabbitmq.exchange.status:status.exchange}")
    private String statusExchange;

    @Value("${rabbitmq.queue.status:status.queue}")
    private String statusQueue;

    @PostConstruct
    public void init() {
        log.info("JobStatusConsumer initialized, listening on queue: {}", statusQueue);
    }

    @RabbitListener(queues = "${rabbitmq.queue.status:status.queue}")
    public void handleStatusUpdate(JobStatusUpdate statusUpdate, Message message) {
        try {
            log.debug("Received status update for job {}: {}",
                    statusUpdate.getJobId(), statusUpdate.getJobStatus());

            jobService.updateJobStatus(statusUpdate);

            rabbitTemplate.execute(channel -> {
                channel.basicAck(message.getMessageProperties().getDeliveryTag(), false);
                return null;
            });

            log.debug("Successfully processed status update for job {}", statusUpdate.getJobId());
        } catch (Exception e) {
            log.error(
                    "Failed to process status update for job {}: {}",
                    statusUpdate.getJobId(),
                    e.getMessage(),
                    e
            );

            handleProcessingFailure(message, e);
        }
    }

    private void handleProcessingFailure(Message message, Exception exception) {
        try {
            // Move to dead letter queue
            String deadLetterExchange = message.getMessageProperties()
                    .getHeader("x-dead-letter-exchange");
            String deadLetterRoutingKey = message.getMessageProperties()
                    .getHeader("x-dead-letter-routing-key");

            if (deadLetterExchange != null && deadLetterRoutingKey != null) {
                rabbitTemplate.send(
                        deadLetterExchange,
                        deadLetterRoutingKey,
                        message
                );

                log.warn("Message moved to dead letter queue due to: {}", exception.getMessage());
            } else {
                // Reject without requeue
                rabbitTemplate.execute(channel -> {
                    channel.basicReject(
                            message.getMessageProperties().getDeliveryTag(),
                            false
                    );
                    return null;
                });
            }

        } catch (Exception e) {
            log.error("Failed to handle message failure: {}", e.getMessage(), e);
        }
    }

    @RabbitListener(queues = "${rabbitmq.queue.status.dlx:status.queue.dlx}")
    public void handleDeadLetterStatusUpdate(byte[] body, Message message) {
        String messageBody = new String(body, StandardCharsets.UTF_8);
        log.error("Received dead letter status update: {}", messageBody);
        log.error("Original headers: {}", message.getMessageProperties().getHeaders());

        // TODO: Implement dead letter handling logic
        // Could send alert, log to external system, or attempt recovery
    }

}
