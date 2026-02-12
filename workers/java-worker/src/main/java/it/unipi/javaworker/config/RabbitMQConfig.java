package it.unipi.javaworker.config;

import lombok.extern.slf4j.Slf4j;
import org.aopalliance.aop.Advice;
import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.config.RetryInterceptorBuilder;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.connection.CachingConnectionFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitAdmin;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.rabbit.listener.RabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.retry.RejectAndDontRequeueRecoverer;
import org.springframework.amqp.support.converter.JacksonJsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.json.JsonMapper;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Configuration
public class RabbitMQConfig {

    @Value("${spring.rabbitmq.host:rabbitmq1}")
    private String host;

    @Value("${spring.rabbitmq.port:5672}")
    private int port;

    @Value("${spring.rabbitmq.username:admin}")
    private String username;

    @Value("${spring.rabbitmq.password:admin}")
    private String password;

    // optional (avoid startup failure if not provided)
    @Value("#{'${distriqueue.worker.queues:job.high,job.medium,job.low}'.split(',')}")
    private List<String> queues;

    @Value("${distriqueue.worker.job.max-retries:3}")
    private int maxRetries;

    @Value("${distriqueue.worker.job.retry-initial-interval:1000}")
    private long initialInterval;

    @Value("${distriqueue.worker.job.retry-multiplier:2.0}")
    private double multiplier;

    @Value("${distriqueue.worker.job.retry-max-interval:10000}")
    private long maxInterval;

    @Bean
    public ConnectionFactory connectionFactory() {
        CachingConnectionFactory cf = new CachingConnectionFactory();
        cf.setHost(host);
        cf.setPort(port);
        cf.setUsername(username);
        cf.setPassword(password);

        cf.setChannelCacheSize(25);
        cf.setPublisherReturns(true);
        cf.setPublisherConfirmType(CachingConnectionFactory.ConfirmType.CORRELATED);

        // milliseconds (5ms was almost certainly not intended)
        cf.setConnectionTimeout(5000);

        return cf;
    }

    @Bean
    public RabbitAdmin rabbitAdmin(ConnectionFactory connectionFactory) {
        return new RabbitAdmin(connectionFactory);
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory, JsonMapper jsonMapper) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(messageConverter(jsonMapper));
        template.setMandatory(true);
        return template;
    }

    @Bean
    public MessageConverter messageConverter(JsonMapper jsonMapper) {
        return new JacksonJsonMessageConverter(jsonMapper);
    }

    @Bean
    public DirectExchange jobsExchange() {
        return ExchangeBuilder.directExchange("jobs.exchange")
                .durable(true)
                .build();
    }

    @Bean
    public Queue highPriorityQueue() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-max-priority", 10);
        args.put("x-dead-letter-exchange", "");
        args.put("x-dead-letter-routing-key", "job.dead-letter");
        return QueueBuilder.durable("job.high").withArguments(args).build();
    }

    @Bean
    public Queue mediumPriorityQueue() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-max-priority", 5);
        args.put("x-dead-letter-exchange", "");
        args.put("x-dead-letter-routing-key", "job.dead-letter");
        return QueueBuilder.durable("job.medium").withArguments(args).build();
    }

    @Bean
    public Queue lowPriorityQueue() {
        Map<String, Object> args = new HashMap<>();
        args.put("x-max-priority", 1);
        args.put("x-dead-letter-exchange", "");
        args.put("x-dead-letter-routing-key", "job.dead-letter");
        return QueueBuilder.durable("job.low").withArguments(args).build();
    }

    @Bean
    public Queue deadLetterQueue() {
        return QueueBuilder.durable("job.dead-letter").build();
    }

    @Bean
    public Binding highPriorityBinding() {
        return BindingBuilder.bind(highPriorityQueue())
                .to(jobsExchange()).with("job.high");
    }

    @Bean
    public Binding mediumPriorityBinding() {
        return BindingBuilder.bind(mediumPriorityQueue())
                .to(jobsExchange()).with("job.medium");
    }

    @Bean
    public Binding lowPriorityBinding() {
        return BindingBuilder.bind(lowPriorityQueue())
                .to(jobsExchange()).with("job.low");
    }

    /**
     * FIX (Boot 4 / AMQP 4):
     * Use Spring AMQP RetryInterceptorBuilder (backed by Spring Framework core retry).
     */
    @Bean
    public Advice retryAdvice() {
        return RetryInterceptorBuilder.stateless()
                .maxRetries(maxRetries) // total attempts = 1 + maxRetries :contentReference[oaicite:3]{index=3}
                .backOffOptions(initialInterval, multiplier, maxInterval)
                .recoverer(new RejectAndDontRequeueRecoverer())
                .build();
    }

    @Bean
    public RabbitListenerContainerFactory<?> rabbitListenerContainerFactory(
            ConnectionFactory connectionFactory,
            JsonMapper jsonMapper
    ) {

        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setMessageConverter(messageConverter(jsonMapper));
        factory.setConcurrentConsumers(3);
        factory.setMaxConcurrentConsumers(10);
        factory.setPrefetchCount(1);

        factory.setDefaultRequeueRejected(false);

        factory.setMissingQueuesFatal(false);
        factory.setAdviceChain(retryAdvice());
        return factory;
    }

}
