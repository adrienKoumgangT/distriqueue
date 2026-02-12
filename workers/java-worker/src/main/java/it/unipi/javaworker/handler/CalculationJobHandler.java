package it.unipi.javaworker.handler;

import it.unipi.javaworker.model.Job;
import it.unipi.javaworker.model.JobResult;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.math3.stat.descriptive.DescriptiveStatistics;
import org.springframework.stereotype.Component;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ThreadLocalRandom;

@Slf4j
@Component
public class CalculationJobHandler implements JobHandler {

    @Override
    public boolean canHandle(String jobType) {
        return Job.Types.CALCULATE.equals(jobType) ||
                Job.Types.SORT.equals(jobType) ||
                Job.Types.AGGREGATE.equals(jobType);
    }

    @Override
    public String getName() {
        return "CalculationJobHandler";
    }

    @Override
    public CompletableFuture<JobResult> handle(Job job) {
        return CompletableFuture.supplyAsync(() -> {
            String jobId = job.getId();
            String workerId = job.getWorkerId();

            log.info("[{}] Starting calculation job: {}", jobId, job.getType());

            try {
                Map<String, Object> payload = job.getPayload();
                String operation = (String) payload.getOrDefault("operation", "sum");
                List<Number> numbers = getNumbersFromPayload(payload);

                if (numbers.isEmpty()) {
                    return JobResult.failure(jobId, workerId, "No numbers provided for calculation");
                }

                Map<String, Object> result = new HashMap<>();

                switch (operation.toLowerCase()) {
                    case "sum":
                        double sum = numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .sum();
                        result.put("sum", sum);
                        result.put("count", numbers.size());
                        break;

                    case "average":
                        double average = numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .average()
                                .orElse(0.0);
                        result.put("average", average);
                        result.put("count", numbers.size());
                        break;

                    case "min":
                        double min = numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .min()
                                .orElse(0.0);
                        result.put("min", min);
                        break;

                    case "max":
                        double max = numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .max()
                                .orElse(0.0);
                        result.put("max", max);
                        break;

                    case "stddev":
                        DescriptiveStatistics stats = new DescriptiveStatistics();
                        numbers.forEach(n -> stats.addValue(n.doubleValue()));
                        result.put("mean", stats.getMean());
                        result.put("stddev", stats.getStandardDeviation());
                        result.put("variance", stats.getVariance());
                        break;

                    case "sort":
                        List<Double> sorted = numbers.stream()
                                .map(Number::doubleValue)
                                .sorted()
                                .toList();
                        result.put("sorted", sorted);
                        result.put("original_count", numbers.size());
                        break;

                    case "aggregate":
                        Map<String, Object> aggregates = new HashMap<>();
                        aggregates.put("sum", numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .sum());
                        aggregates.put("average", numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .average()
                                .orElse(0.0));
                        aggregates.put("count", numbers.size());
                        aggregates.put("min", numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .min()
                                .orElse(0.0));
                        aggregates.put("max", numbers.stream()
                                .mapToDouble(Number::doubleValue)
                                .max()
                                .orElse(0.0));
                        result.put("aggregates", aggregates);
                        break;

                    default:
                        return JobResult.failure(jobId, workerId,
                                "Unsupported operation: " + operation);
                }

                simulateProcessing(numbers.size());

                log.info("[{}] Calculation completed successfully", jobId);
                return JobResult.success(jobId, workerId, result);

            } catch (Exception e) {
                log.error("[{}] Calculation failed: {}", jobId, e.getMessage(), e);
                return JobResult.failure(jobId, workerId, "Calculation error: " + e.getMessage());
            }
        });
    }

    private List<Number> getNumbersFromPayload(Map<String, Object> payload) {
        List<Number> numbers = new ArrayList<>();

        Object numbersObj = payload.get("numbers");
        if (numbersObj instanceof List) {
            ((List<?>) numbersObj).forEach(item -> {
                if (item instanceof Number) {
                    numbers.add((Number) item);
                }
            });
        }

        // If no numbers in payload, generate random ones
        if (numbers.isEmpty()) {
            int count = (int) payload.getOrDefault("count", 100);
            for (int i = 0; i < count; i++) {
                numbers.add(ThreadLocalRandom.current().nextDouble(0, 1000));
            }
        }

        return numbers;
    }

    private void simulateProcessing(int dataSize) {
        try {
            // Simulate CPU-intensive work
            int processingTime = Math.min(5000, dataSize * 10); // Max 5 seconds
            processingTime = Math.max(100, processingTime); // Min 100ms

            // Report progress periodically
            int steps = processingTime / 100;
            for (int i = 0; i < steps; i++) {
                Thread.sleep(100);
                if (i % 5 == 0) {
                    int progress = (i * 100) / steps;
                    log.debug("Calculation progress: {}%", progress);
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

}
