package it.unipi.gateway.model;

import lombok.Getter;

@Getter
public enum JobPriority {
    LOW(1),
    MEDIUM(5),
    HIGH(10),
    CRITICAL(15),
    ;

    private final int value;

    JobPriority(int value) {
        this.value = value;
    }

    public static JobPriority fromValue(int value) {
        for (JobPriority jobPriority : JobPriority.values()) {
            if (jobPriority.getValue() == value) {
                return jobPriority;
            }
        }
        throw new IllegalArgumentException("Invalid priority value: " + value);
    }

}
