package it.unipi.gateway.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import it.unipi.gateway.model.*;
import it.unipi.gateway.service.JobService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.time.LocalDateTime;

@RequiredArgsConstructor
@RestController
@RequestMapping("/jobs")
@Validated
@Tag(name = "Jobs", description = "Job management endpoints")
public class JobController {

    private final JobService jobService;

    @Operation(summary = "Submit a new job")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "202", description = "Job accepted"),
            @ApiResponse(responseCode = "400", description = "Invalid request"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    @PostMapping
    public ResponseEntity<JobResponse> submitJob(
            @Valid @RequestBody JobRequest request
    ) {
        request.validate();
        Job job = jobService.createJob(request);
        JobResponse response = JobResponse.fromEntity(job);

        return ResponseEntity
                .status(HttpStatus.ACCEPTED)
                .header("Location", "/v1/jobs/" + job.getId())
                .body(response);
    }

    @Operation(summary = "Get job by ID")
    @GetMapping("/{id}")
    public ResponseEntity<JobResponse> getJob(
            @Parameter(description = "Job ID") @PathVariable String id
    ) {

        return jobService.getJob(id)
                .map(job -> ResponseEntity.ok(JobResponse.fromEntity(job)))
                .orElse(ResponseEntity.notFound().build());
    }

    @Operation(summary = "Get jobs with filtering")
    @GetMapping
    public ResponseEntity<Page<JobResponse>> getJobs(
            @Parameter(description = "Job type filter") @RequestParam(required = false) String type,
            @Parameter(description = "Priority filter") @RequestParam(required = false) JobPriority jobPriority,
            @Parameter(description = "Status filter") @RequestParam(required = false) JobStatus jobStatus,
            @Parameter(description = "Created from (ISO date)") @RequestParam(required = false) LocalDateTime createdFrom,
            @Parameter(description = "Created to (ISO date)") @RequestParam(required = false) LocalDateTime createdTo,
            @Parameter(description = "Page number (0-based)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size") @RequestParam(defaultValue = "20") int size,
            @Parameter(description = "Sort field") @RequestParam(defaultValue = "createdAt") String sortBy,
            @Parameter(description = "Sort direction") @RequestParam(defaultValue = "DESC") String sortDirection
    ) {

        JobFilterCriteria criteria = JobFilterCriteria.builder()
                .type(type)
                .jobPriority(jobPriority)
                .jobStatus(jobStatus)
                .createdFrom(createdFrom)
                .createdTo(createdTo)
                .page(page)
                .size(size)
                .sortBy(sortBy)
                .sortDirection(sortDirection)
                .build();

        criteria.validate();

        Page<JobResponse> jobs = jobService.getJobs(criteria);
        return ResponseEntity.ok(jobs);
    }

    @Operation(summary = "Submit multiple jobs in batch")
    @PostMapping("/batch")
    public ResponseEntity<JobBatchResponse> submitBatch(
            @Valid @RequestBody JobBatchRequest request
    ) {

        request.validate();
        JobBatchResponse response = jobService.submitBatch(request);
        return ResponseEntity.accepted().body(response);
    }

    @Operation(summary = "Cancel a job")
    @PostMapping("/{id}/cancel")
    public ResponseEntity<JobResponse> cancelJob(@PathVariable String id
    ) {
        return jobService.cancelJob(id)
                .map(job -> ResponseEntity.ok(JobResponse.fromEntity(job)))
                .orElse(ResponseEntity.notFound().build());
    }

    @Operation(summary = "Retry a failed job")
    @PostMapping("/{id}/retry")
    public ResponseEntity<JobResponse> retryJob(@PathVariable String id) {
        return jobService.retryJob(id)
                .map(job -> ResponseEntity.ok(JobResponse.fromEntity(job)))
                .orElse(ResponseEntity.notFound().build());
    }

    @Operation(summary = "Get job statistics")
    @GetMapping("/statistics")
    public ResponseEntity<JobStatistics> getStatistics(
            @RequestParam(required = false) LocalDateTime from,
            @RequestParam(required = false) LocalDateTime to
    ) {

        JobStatistics statistics = jobService.getStatistics(from, to);
        return ResponseEntity.ok(statistics);
    }

    @Operation(summary = "Stream real-time job updates")
    @GetMapping("/stream")
    public SseEmitter streamJobUpdates() {
        return jobService.createJobStream();
    }

}
