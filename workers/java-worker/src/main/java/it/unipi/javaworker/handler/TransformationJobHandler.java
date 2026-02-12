package it.unipi.javaworker.handler;

import it.unipi.javaworker.model.Job;
import it.unipi.javaworker.model.JobResult;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;

@Slf4j
@Component
public class TransformationJobHandler implements JobHandler {

    @Override
    public boolean canHandle(String jobType) {
        return Job.Types.TRANSFORM.equals(jobType) ||
                Job.Types.FILTER.equals(jobType);
    }

    @Override
    public String getName() {
        return "TransformationJobHandler";
    }

    @Override
    public CompletableFuture<JobResult> handle(Job job) {
        return CompletableFuture.supplyAsync(() -> {
            String jobId = job.getId();
            String workerId = job.getWorkerId();

            log.info("[{}] Starting transformation job: {}", jobId, job.getType());

            try {
                Map<String, Object> payload = job.getPayload();
                Map<String, Object> data = (Map<String, Object>) payload.getOrDefault("data", new HashMap<>());
                String operation = (String) payload.getOrDefault("operation", "uppercase");

                Map<String, Object> result = new HashMap<>();
                Map<String, Object> transformed = new HashMap<>();

                switch (operation.toLowerCase()) {
                    case "uppercase":
                        for (Map.Entry<String, Object> entry : data.entrySet()) {
                            transformed.put(entry.getKey().toUpperCase(),
                                    entry.getValue().toString().toUpperCase());
                        }
                        result.put("transformed", transformed);
                        result.put("operation", "uppercase");
                        break;

                    case "lowercase":
                        for (Map.Entry<String, Object> entry : data.entrySet()) {
                            transformed.put(entry.getKey().toLowerCase(),
                                    entry.getValue().toString().toLowerCase());
                        }
                        result.put("transformed", transformed);
                        result.put("operation", "lowercase");
                        break;

                    case "reverse":
                        for (Map.Entry<String, Object> entry : data.entrySet()) {
                            String key = new StringBuilder(entry.getKey()).reverse().toString();
                            String value = new StringBuilder(entry.getValue().toString()).reverse().toString();
                            transformed.put(key, value);
                        }
                        result.put("transformed", transformed);
                        result.put("operation", "reverse");
                        break;

                    case "filter":
                        String filterKey = (String) payload.get("filter_key");
                        Object filterValue = payload.get("filter_value");

                        if (filterKey != null && filterValue != null) {
                            transformed = data.entrySet().stream()
                                    .filter(entry -> filterValue.equals(entry.getValue()))
                                    .collect(Collectors.toMap(
                                            Map.Entry::getKey,
                                            Map.Entry::getValue
                                    ));
                        } else {
                            // Filter numeric values > 0
                            transformed = data.entrySet().stream()
                                    .filter(entry -> {
                                        Object value = entry.getValue();
                                        if (value instanceof Number) {
                                            return ((Number) value).doubleValue() > 0;
                                        }
                                        return false;
                                    })
                                    .collect(Collectors.toMap(
                                            Map.Entry::getKey,
                                            Map.Entry::getValue
                                    ));
                        }
                        result.put("filtered", transformed);
                        result.put("original_count", data.size());
                        result.put("filtered_count", transformed.size());
                        break;

                    case "normalize":
                        // Normalize numeric values to 0-1 range
                        if (!data.isEmpty()) {
                            double max = data.values().stream()
                                    .filter(v -> v instanceof Number)
                                    .mapToDouble(v -> ((Number) v).doubleValue())
                                    .max()
                                    .orElse(1.0);

                            double min = data.values().stream()
                                    .filter(v -> v instanceof Number)
                                    .mapToDouble(v -> ((Number) v).doubleValue())
                                    .min()
                                    .orElse(0.0);

                            double range = max - min;
                            if (range == 0) range = 1;

                            for (Map.Entry<String, Object> entry : data.entrySet()) {
                                Object value = entry.getValue();
                                if (value instanceof Number) {
                                    double normalized = (((Number) value).doubleValue() - min) / range;
                                    transformed.put(entry.getKey(), normalized);
                                } else {
                                    transformed.put(entry.getKey(), value);
                                }
                            }
                            result.put("normalized", transformed);
                            result.put("min", min);
                            result.put("max", max);
                        }
                        break;

                    default:
                        return JobResult.failure(jobId, workerId,
                                "Unsupported transformation: " + operation);
                }

                simulateProcessing(data.size());

                log.info("[{}] Transformation completed successfully", jobId);
                return JobResult.success(jobId, workerId, result);

            } catch (Exception e) {
                log.error("[{}] Transformation failed: {}", jobId, e.getMessage(), e);
                return JobResult.failure(jobId, workerId, "Transformation error: " + e.getMessage());
            }
        });
    }

    private void simulateProcessing(int dataSize) {
        try {
            int processingTime = Math.min(3000, dataSize * 5); // Max 3 seconds
            processingTime = Math.max(50, processingTime); // Min 50ms
            Thread.sleep(processingTime);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

}
