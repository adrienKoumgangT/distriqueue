package it.unipi.gateway.model;

import lombok.*;

import java.time.LocalDateTime;

@Data
@Builder
@AllArgsConstructor
public class WorkerHealth {

    private String workerId;
    private String workerType;
    private WorkerStatus status;
    private LocalDateTime lastHeartbeat;
    private int capacity;
    private int currentLoad;
    private double cpuUsage;
    private double memoryUsage;
    private LocalDateTime registeredAt;

    public WorkerHealth(String workerId, String workerType) {
        this.workerId = workerId;
        this.workerType = workerType;
        this.status = WorkerStatus.ACTIVE;
        this.registeredAt = LocalDateTime.now();
    }

    public double getUtilizationPercentage() {
        if (capacity == 0) return 0.0;
        return (currentLoad * 100.0) / capacity;
    }

    public boolean isHealthy() {
        return status == WorkerStatus.ACTIVE &&
                lastHeartbeat != null &&
                lastHeartbeat.plusMinutes(5).isAfter(LocalDateTime.now());
    }

}
