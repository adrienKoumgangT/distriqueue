package it.unipi.javaworker.handler;

import it.unipi.javaworker.model.Job;
import it.unipi.javaworker.model.JobResult;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.regex.Pattern;

@Slf4j
@Component
public class ValidationJobHandler implements JobHandler {

    private static final Pattern EMAIL_PATTERN = Pattern.compile("^[A-Za-z0-9+_.-]+@(.+)$");

    private static final Pattern PHONE_PATTERN = Pattern.compile("^\\+?[1-9]\\d{1,14}$");

    @Override
    public boolean canHandle(String jobType) {
        return Job.Types.VALIDATE.equals(jobType);
    }

    @Override
    public String getName() {
        return "ValidationJobHandler";
    }

    @Override
    public CompletableFuture<JobResult> handle(Job job) {
        return CompletableFuture.supplyAsync(() -> {
            String jobId = job.getId();
            String workerId = job.getWorkerId();

            log.info("[{}] Starting validation job", jobId);

            try {
                Map<String, Object> payload = job.getPayload();
                Object value = payload.get("value");
                String validationType = (String) payload.getOrDefault("type", "generic");

                Map<String, Object> result = new HashMap<>();
                boolean isValid = false;
                String message = "";

                switch (validationType.toLowerCase()) {
                    case "email":
                        isValid = isValidEmail(value);
                        message = isValid ? "Valid email address" : "Invalid email address";
                        result.put("type", "email");
                        break;

                    case "phone":
                        isValid = isValidPhone(value);
                        message = isValid ? "Valid phone number" : "Invalid phone number";
                        result.put("type", "phone");
                        break;

                    case "numeric":
                        isValid = isNumeric(value);
                        message = isValid ? "Valid number" : "Invalid number";
                        result.put("type", "numeric");
                        if (isValid && value != null) {
                            result.put("parsed", Double.parseDouble(value.toString()));
                        }
                        break;

                    case "required":
                        isValid = isRequired(value);
                        message = isValid ? "Value is present" : "Value is required but missing";
                        result.put("type", "required");
                        break;

                    case "range":
                        double min = ((Number) payload.getOrDefault("min", 0)).doubleValue();
                        double max = ((Number) payload.getOrDefault("max", 100)).doubleValue();
                        isValid = isInRange(value, min, max);
                        message = isValid ?
                                String.format("Value is in range [%f, %f]", min, max) :
                                String.format("Value is outside range [%f, %f]", min, max);
                        result.put("type", "range");
                        result.put("min", min);
                        result.put("max", max);
                        break;

                    case "length":
                        int minLength = (int) payload.getOrDefault("min_length", 0);
                        int maxLength = (int) payload.getOrDefault("max_length", 100);
                        isValid = isValidLength(value, minLength, maxLength);
                        message = isValid ?
                                String.format("Length is within [%d, %d]", minLength, maxLength) :
                                String.format("Length is outside [%d, %d]", minLength, maxLength);
                        result.put("type", "length");
                        result.put("min_length", minLength);
                        result.put("max_length", maxLength);
                        break;

                    case "regex":
                        String pattern = (String) payload.get("pattern");
                        if (pattern != null) {
                            isValid = matchesPattern(value, pattern);
                            message = isValid ? "Matches pattern" : "Does not match pattern";
                            result.put("type", "regex");
                            result.put("pattern", pattern);
                        } else {
                            return JobResult.failure(jobId, workerId,
                                    "Pattern is required for regex validation");
                        }
                        break;

                    default:
                        // Generic validation
                        isValid = value != null && !value.toString().trim().isEmpty();
                        message = isValid ? "Value is valid" : "Value is invalid or empty";
                        result.put("type", "generic");
                }

                result.put("is_valid", isValid);
                result.put("message", message);
                result.put("value", value);

                simulateProcessing();

                log.info("[{}] Validation completed: {}", jobId, message);
                return JobResult.success(jobId, workerId, result);

            } catch (Exception e) {
                log.error("[{}] Validation failed: {}", jobId, e.getMessage(), e);
                return JobResult.failure(jobId, workerId, "Validation error: " + e.getMessage());
            }
        });
    }

    private boolean isValidEmail(Object value) {
        if (value == null) return false;
        return EMAIL_PATTERN.matcher(value.toString()).matches();
    }

    private boolean isValidPhone(Object value) {
        if (value == null) return false;
        return PHONE_PATTERN.matcher(value.toString().replaceAll("[\\s-()]", "")).matches();
    }

    private boolean isNumeric(Object value) {
        if (value == null) return false;
        try {
            Double.parseDouble(value.toString());
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    private boolean isRequired(Object value) {
        return value != null && !value.toString().trim().isEmpty();
    }

    private boolean isInRange(Object value, double min, double max) {
        if (!isNumeric(value)) return false;
        double num = Double.parseDouble(value.toString());
        return num >= min && num <= max;
    }

    private boolean isValidLength(Object value, int minLength, int maxLength) {
        if (value == null) return minLength == 0;
        int length = value.toString().length();
        return length >= minLength && length <= maxLength;
    }

    private boolean matchesPattern(Object value, String pattern) {
        if (value == null) return false;
        try {
            Pattern compiled = Pattern.compile(pattern);
            return compiled.matcher(value.toString()).matches();
        } catch (Exception e) {
            return false;
        }
    }

    private void simulateProcessing() {
        try {
            Thread.sleep(100 + (long) (Math.random() * 400)); // 100-500ms
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

}
