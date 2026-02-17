package it.unipi.gateway.config;

import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.json.JsonMapper;

@Configuration
public class RabbitMQConfig {

    public static final String HIGH_PRIORITY_QUEUE = "jobs.high";
    public static final String MEDIUM_PRIORITY_QUEUE = "jobs.medium";
    public static final String LOW_PRIORITY_QUEUE = "jobs.low";

    @Bean
    public Queue highPriorityQueue() {
        return QueueBuilder.durable(HIGH_PRIORITY_QUEUE)
                .maxPriority(10)
                .quorum()
                .build();
    }

    @Bean
    public Queue mediumPriorityQueue() {
        return QueueBuilder.durable(MEDIUM_PRIORITY_QUEUE)
                .maxPriority(5)
                .quorum()
                .build();
    }

    @Bean
    public Queue lowPriorityQueue() {
        return QueueBuilder.durable(LOW_PRIORITY_QUEUE)
                .maxPriority(1)
                .quorum()
                .build();
    }

    @Bean
    public MessageConverter messageConverter(JsonMapper jsonMapper) {
        return new JacksonJsonMessageConverter(jsonMapper);
    }

    @Bean
    public RabbitTemplate rabbitTemplate(
            ConnectionFactory connectionFactory,
            JsonMapper jsonMapper
    ) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(messageConverter(jsonMapper));
        return template;
    }

}
