package it.unipi.gateway.config;

import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.json.JsonMapper;

import java.util.HashMap;
import java.util.Map;

@Configuration
public class RabbitMQConfig {

    public static final String HIGH_PRIORITY_QUEUE = "job.high";
    public static final String MEDIUM_PRIORITY_QUEUE = "job.medium";
    public static final String LOW_PRIORITY_QUEUE = "job.low";

    @Bean
    public Queue highPriorityQueue() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-max-priority", 10);
        return QueueBuilder.durable(HIGH_PRIORITY_QUEUE).withArguments(args).build();
    }

    @Bean
    public Queue mediumPriorityQueue() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-max-priority", 5);
        return QueueBuilder.durable(MEDIUM_PRIORITY_QUEUE).withArguments(args).build();
    }

    @Bean
    public Queue lowPriorityQueue() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-max-priority", 1);
        return QueueBuilder.durable(LOW_PRIORITY_QUEUE).withArguments(args).build();
    }

    // Explicit exchange and binding for status updates
    @Bean
    public TopicExchange statusExchange() {
        return new TopicExchange("status.exchange");
    }

    // Status queues for the Gateway to listen to
    @Bean
    public Queue statusQueue() {
        return QueueBuilder.durable("status.queue")
                .withArgument("x-dead-letter-exchange", "status.dlx")
                .withArgument("x-dead-letter-routing-key", "status.dlq")
                .build();
    }

    @Bean
    public Binding statusBinding(@Qualifier("statusQueue") Queue statusQueue, TopicExchange statusExchange) {
        return BindingBuilder.bind(statusQueue).to(statusExchange).with("#");
    }

    @Bean
    public Queue statusDlq() {
        return QueueBuilder.durable("status.queue.dlx").build();
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
