package it.unipi.javaworker.util;

import lombok.extern.slf4j.Slf4j;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.function.Predicate;

@Slf4j
public class RetryUtils {

    public static <T> Mono<T> withRetry(Mono<T> mono, int maxRetries, Duration delay) {
        return mono.retryWhen(Retry.from(companion ->
                companion.flatMap(retrySignal -> {
                    long attempt = retrySignal.totalRetriesInARow() + 1;

                    if (attempt > maxRetries) {
                        log.error("Max retries ({}) exceeded", maxRetries);
                        return Mono.error(retrySignal.failure());
                    }

                    log.info("Retry attempt {}/{} after {}ms", attempt, maxRetries, delay.toMillis());

                    return Mono.delay(delay);
                })
        ));
    }

    public static <T> Mono<T> withFixedDelayRetry(Mono<T> mono, int maxRetries, Duration delay) {
        return mono.retryWhen(Retry.from(companion ->
                companion.flatMap(retrySignal -> {
                    if (retrySignal.totalRetries() >= maxRetries) {
                        return Mono.error(retrySignal.failure());
                    }
                    log.info("Retry attempt {}/{} after {}ms", retrySignal.totalRetries() + 1, maxRetries, delay.toMillis());
                    return Mono.delay(delay);
                })
        ));
    }

    /**
     * Reactor's built-in Retry.fixedDelay (Best Practice)
     */
    public static <T> Mono<T> withReactorFixedDelayRetry(Mono<T> mono, int maxRetries, Duration delay) {
        return mono.retryWhen(
                Retry.fixedDelay(maxRetries, delay)
                        .doBeforeRetry(retrySignal ->
                                log.info(
                                        "Retry attempt {}/{} after {}ms",
                                        retrySignal.totalRetries() + 1,
                                        maxRetries,
                                        delay.toMillis()
                                )
                        )
                        .onRetryExhaustedThrow((spec, retrySignal) -> {
                            log.error("Max retries ({}) exceeded", maxRetries);
                            return retrySignal.failure();
                        })
        );
    }

    /**
     * Exponential backoff retry
     */
    public static <T> Mono<T> withExponentialBackoffRetry(
            Mono<T> mono,
            int maxRetries,
            Duration minDelay,
            Duration maxDelay
    ) {
        return mono.retryWhen(
                Retry.backoff(maxRetries, minDelay)
                        .maxBackoff(maxDelay)
                        .jitter(0.5)
                        .doBeforeRetry(retrySignal ->
                                log.info(
                                        "Retry attempt {}/{} with backoff",
                                        retrySignal.totalRetries() + 1,
                                        maxRetries
                                )
                        )
                        .onRetryExhaustedThrow((spec, retrySignal) -> {
                            log.error("Max retries ({}) exceeded with backoff", maxRetries);
                            return retrySignal.failure();
                        })
        );
    }

    /**
     * Conditional retry based on exception type
     */
    public static <T> Mono<T> withConditionalRetry(
            Mono<T> mono,
            int maxRetries,
            Duration delay,
            Predicate<? super Throwable> retryCondition
    ) {
        return mono.retryWhen(
                Retry.fixedDelay(maxRetries, delay)
                        .filter(retryCondition)
                        .doBeforeRetry(retrySignal ->
                                log.info("Retry attempt {}/{} for condition", retrySignal.totalRetries() + 1, maxRetries)
                        )
                        .onRetryExhaustedThrow((spec, retrySignal) -> {
                            log.error("Max retries ({}) exceeded for conditional retry", maxRetries);
                            return retrySignal.failure();
                        })
        );
    }

    /**
     * Dynamic delay calculation using modern zipWith context.
     */
    public static <T> Mono<T> withDynamicDelayRetry(
            Mono<T> mono,
            int maxRetries,
            DelayFunction delayFunction
    ) {
        return mono.retryWhen(Retry.from(companion ->
                companion.flatMap(retrySignal -> {
                    long attempt = retrySignal.totalRetries() + 1;
                    if (attempt > maxRetries) {
                        return Mono.error(retrySignal.failure());
                    }

                    Duration delay = delayFunction.calculateDelay((int) attempt);
                    log.info("Retry attempt {}/{} after {}ms", attempt, maxRetries, delay.toMillis());

                    return Mono.delay(delay);
                })
        ));
    }

    /**
     * Standard exponential backoff implementation.
     * Starts with the provided delay and doubles it each attempt (up to a default max).
     *
     * @param maxRetries Maximum number of retry attempts.
     * @param minDelay   Initial delay for the first retry.
     * @return A Mono configured with exponential backoff.
     */
    public static <T> Mono<T> exponentialBackoff(Mono<T> mono, int maxRetries, Duration minDelay) {
        return mono.retryWhen(
                Retry.backoff(maxRetries, minDelay)
                        // By default, backoff doubles the delay each time
                        .jitter(0.5) // 0.5 is standard to prevent "thundering herd" issues
                        .doBeforeRetry(retrySignal ->
                                log.info(
                                        "Retry attempt {}/{} with exponential backoff. Current failure: {}",
                                        retrySignal.totalRetries() + 1,
                                        maxRetries,
                                        retrySignal.failure().getMessage()
                                )
                        )
                        .onRetryExhaustedThrow((spec, retrySignal) -> {
                            log.error("Exponential backoff retries exhausted after {} attempts", maxRetries);
                            return retrySignal.failure();
                        })
        );
    }

    public static Retry exponentialBackoff(int maxRetries, Duration minDelay) {
        return Retry.backoff(maxRetries, minDelay)
                .jitter(0.75)
                .doBeforeRetry(retrySignal ->
                        log.info(
                                "Retry attempt {}/{} after error: {}",
                                retrySignal.totalRetries() + 1,
                                maxRetries,
                                retrySignal.failure().getMessage()
                        )
                )
                .onRetryExhaustedThrow((spec, signal) -> signal.failure());
    }

    @FunctionalInterface
    public interface DelayFunction {
        Duration calculateDelay(int attempt);
    }

}