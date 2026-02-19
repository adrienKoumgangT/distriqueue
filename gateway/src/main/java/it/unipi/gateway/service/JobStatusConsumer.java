package it.unipi.gateway.service;

import it.unipi.gateway.model.JobStatusUpdate;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.stereotype.Service;
import tools.jackson.databind.json.JsonMapper;

import java.nio.charset.StandardCharsets;

@Slf4j
@Service
@RequiredArgsConstructor
public class JobStatusConsumer {

    private final JobService jobService;

    private final JsonMapper jsonMapper;

    @PostConstruct
    public void init() {
        log.info("JobStatusConsumer initialized, listening on queue: status.queue");
    }

    @RabbitListener(queues = "${rabbitmq.queue.status:status.queue}")
    public void handleStatusUpdate(Message message) {
        try {
            String rawJson = new String(message.getBody(), StandardCharsets.UTF_8);
            log.info("RAW STATUS UPDATE FROM ERLANG: {}", rawJson);

            JobStatusUpdate statusUpdate = jsonMapper.readValue(rawJson, JobStatusUpdate.class);

            log.info("Parsed status update for job {}: {}", statusUpdate.getJobId(), statusUpdate.getJobStatus());

            jobService.updateJobStatus(statusUpdate);
        } catch (Exception e) {
            log.error("Failed to process status update from Erlang: {}", e.getMessage(), e);
            throw new RuntimeException("Message processing failed", e);
        }
    }

    @RabbitListener(queues = "${rabbitmq.queue.status.dlx:status.queue.dlx}")
    public void handleDeadLetterStatusUpdate(Message message) {
        String messageBody = new String(message.getBody(), StandardCharsets.UTF_8);
        log.error("Received dead letter status update: {}", messageBody);
        log.error("Original headers: {}", message.getMessageProperties().getHeaders());
    }

}
