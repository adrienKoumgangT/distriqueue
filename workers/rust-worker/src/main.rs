use lapin::{
    options::*, types::FieldTable, Connection, ConnectionProperties,
    Consumer, message::DeliveryResult,
};
use futures_lite::stream::StreamExt;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::env;
use std::sync::Arc;
use tokio::sync::{Mutex, Semaphore};
use uuid::Uuid;
use chrono::Utc;
use log::{info, error, debug, warn};

// --- Models ---
#[derive(Debug, Serialize, Deserialize)]
struct Job {
    id: String,
    #[serde(rename = "type", default = "default_type")]
    job_type: String,
    payload: Option<Value>,
    retry_count: Option<u32>,
    max_retries: Option<u32>,
}

fn default_type() -> String { "default".to_string() }

// --- Job Handler Trait ---
#[async_trait::async_trait]
trait JobHandler: Send + Sync {
    fn can_handle(&self, job_type: &str) -> bool;
    async fn execute(&self, job: &Job) -> Value;
    fn get_name(&self) -> &str;
}

// --- Calculation Handler Implementation ---
struct CalculationJobHandler;

#[async_trait::async_trait]
impl JobHandler for CalculationJobHandler {
    fn can_handle(&self, job_type: &str) -> bool {
        let types = ["calculate", "sum", "average"];
        types.contains(&job_type)
    }

    async fn execute(&self, job: &Job) -> Value {
        let start_time = std::time::Instant::now();
        let payload = job.payload.as_ref();

        let operation = payload.and_then(|p| p.get("operation"))
            .and_then(|o| o.as_str())
            .unwrap_or("sum");

        let numbers: Vec<f64> = payload.and_then(|p| p.get("numbers"))
            .and_then(|n| n.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_f64()).collect())
            .unwrap_or_else(|| vec![1.0, 2.0, 3.0]); // Default if none provided

        let mut result = serde_json::Map::new();

        match operation {
            "sum" => {
                let sum: f64 = numbers.iter().sum();
                result.insert("sum".to_string(), json!(sum));
                result.insert("count".to_string(), json!(numbers.len()));
            },
            "average" => {
                let sum: f64 = numbers.iter().sum();
                let avg = if numbers.is_empty() { 0.0 } else { sum / numbers.len() as f64 };
                result.insert("average".to_string(), json!(avg));
            },
            _ => {
                result.insert("error".to_string(), json!("Unknown operation"));
            }
        }

        let duration = start_time.elapsed().as_millis() as u64;
        result.insert("processing_time_ms".to_string(), json!(duration));

        Value::Object(result)
    }

    fn get_name(&self) -> &str {
        "CalculationJobHandler"
    }
}


// --- Transformation Handler Implementation ---
struct TransformationJobHandler;

#[async_trait::async_trait]
impl JobHandler for TransformationJobHandler {
    fn can_handle(&self, job_type: &str) -> bool {
        let types = ["transform", "uppercase", "lowercase", "reverse", "filter", "normalize"];
        types.contains(&job_type)
    }

    async fn execute(&self, job: &Job) -> Value {
        let start_time = std::time::Instant::now();
        let payload = job.payload.as_ref();

        let operation = payload.and_then(|p| p.get("operation"))
            .and_then(|o| o.as_str())
            .unwrap_or("uppercase");

        // Extract the "data" dictionary
        let data = payload.and_then(|p| p.get("data"))
            .and_then(|d| d.as_object())
            .cloned()
            .unwrap_or_default();

        let mut result = serde_json::Map::new();
        let mut transformed = serde_json::Map::new();

        match operation {
            "uppercase" => {
                for (k, v) in &data {
                    let val_str = match v {
                        Value::String(s) => s.to_uppercase(),
                        _ => v.to_string().to_uppercase(),
                    };
                    transformed.insert(k.to_uppercase(), json!(val_str));
                }
                result.insert("transformed".to_string(), Value::Object(transformed));
                result.insert("operation".to_string(), json!("uppercase"));
            },
            "lowercase" => {
                for (k, v) in &data {
                    let val_str = match v {
                        Value::String(s) => s.to_lowercase(),
                        _ => v.to_string().to_lowercase(),
                    };
                    transformed.insert(k.to_lowercase(), json!(val_str));
                }
                result.insert("transformed".to_string(), Value::Object(transformed));
                result.insert("operation".to_string(), json!("lowercase"));
            },
            "reverse" => {
                for (k, v) in &data {
                    let key_rev: String = k.chars().rev().collect();
                    let val_str = match v {
                        Value::String(s) => s.clone(),
                        _ => v.to_string(),
                    };
                    let val_rev: String = val_str.chars().rev().collect();
                    transformed.insert(key_rev, json!(val_rev));
                }
                result.insert("transformed".to_string(), Value::Object(transformed));
                result.insert("operation".to_string(), json!("reverse"));
            },
            "filter" => {
                let filter_key = payload.and_then(|p| p.get("filter_key")).and_then(|v| v.as_str());
                let filter_value = payload.and_then(|p| p.get("filter_value")).and_then(|v| v.as_str());

                if let (Some(fk), Some(fv)) = (filter_key, filter_value) {
                    for (k, v) in &data {
                        let val_str = match v {
                            Value::String(s) => s.clone(),
                            _ => v.to_string(),
                        };
                        if k.contains(fk) || val_str.contains(fv) {
                            transformed.insert(k.clone(), v.clone());
                        }
                    }
                } else {
                    // Filter numeric values > 0
                    for (k, v) in &data {
                        if let Some(num) = v.as_f64() {
                            if num > 0.0 {
                                transformed.insert(k.clone(), v.clone());
                            }
                        }
                    }
                }

                let filtered_count = transformed.len();
                result.insert("filtered".to_string(), Value::Object(transformed));
                result.insert("original_count".to_string(), json!(data.len()));
                result.insert("filtered_count".to_string(), json!(filtered_count));
            },
            "normalize" => {
                // Extract numeric values to find min and max
                let nums: Vec<f64> = data.values().filter_map(|v| v.as_f64()).collect();

                if !nums.is_empty() {
                    let min_val = nums.iter().cloned().fold(f64::INFINITY, f64::min);
                    let max_val = nums.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
                    let range = if max_val > min_val { max_val - min_val } else { 1.0 };

                    for (k, v) in &data {
                        if let Some(num) = v.as_f64() {
                            let norm = (num - min_val) / range;
                            transformed.insert(k.clone(), json!(norm));
                        } else {
                            transformed.insert(k.clone(), v.clone());
                        }
                    }
                    result.insert("normalized".to_string(), Value::Object(transformed));
                    result.insert("min".to_string(), json!(min_val));
                    result.insert("max".to_string(), json!(max_val));
                }
            },
            _ => {
                result.insert("error".to_string(), json!("Unknown operation"));
            }
        }

        // Async sleep to simulate processing time
        let delay_ms = (data.len() as u64 * 50).min(2000);
        tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;

        let duration = start_time.elapsed().as_millis() as u64;
        result.insert("processing_time_ms".to_string(), json!(duration));

        Value::Object(result)
    }

    fn get_name(&self) -> &str {
        "TransformationJobHandler"
    }
}


// --- Worker State ---
struct WorkerMetrics {
    current_load: u32,
    total_processed: u32,
    successful_jobs: u32,
    failed_jobs: u32,
}

struct WorkerContext {
    worker_id: String,
    worker_type: String,
    status_url: String,
    orchestrator_url: String,
    handlers: Vec<Box<dyn JobHandler>>,
    http_client: Client,
    capacity: u32,
    metrics: Mutex<WorkerMetrics>,
}

impl WorkerContext {
    async fn send_status(&self, job_id: &str, status: &str, result: Option<Value>, err: Option<&str>) {
        let mut payload = json!({
            "jobId": job_id,
            "status": status,
            "workerId": self.worker_id,
            "timestamp": Utc::now().to_rfc3339()
        });

        if let Some(r) = result {
            payload["result"] = r;
        }
        if let Some(e) = err {
            payload["errorMessage"] = json!(e);
        }

        match self.http_client.post(&self.status_url).json(&payload).send().await {
            Ok(res) if res.status().is_success() => debug!("[{}] Status sent: {}", job_id, status),
            Ok(res) => warn!("[{}] Status update failed: {}", job_id, res.status()),
            Err(e) => error!("[{}] Failed to send status: {}", job_id, e),
        }
    }

    async fn send_heartbeat(&self) {
        // Quickly lock metrics to copy the current numbers
        let (load, processed, success, fail) = {
            let m = self.metrics.lock().await;
            (m.current_load, m.total_processed, m.successful_jobs, m.failed_jobs)
        };

        let payload = json!({
            "worker_id": self.worker_id,
            "worker_type": self.worker_type,
            "capacity": self.capacity,
            "current_load": load,
            "total_jobs_processed": processed,
            "successful_jobs": success,
            "failed_jobs": fail,
            "timestamp": Utc::now().timestamp_millis()
        });

        let url = format!("{}/api/workers/heartbeat", self.orchestrator_url);

        match self.http_client.post(&url).json(&payload).send().await {
            Ok(res) if res.status().is_success() => {
                debug!("Heartbeat sent, load: {}/{}", load, self.capacity);
            }
            Ok(res) => warn!("Heartbeat failed: {}", res.status()),
            Err(e) => error!("Heartbeat HTTP error: {}", e),
        }
    }
}

// --- Main Worker Logic ---
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();

    // Configuration
    let rm_host = env::var("RABBITMQ_HOST")
        .unwrap_or_else(|_| "10.2.1.11".to_string());
    let rm_port = env::var("RABBITMQ_PORT")
        .unwrap_or_else(|_| "5672".to_string());
    let rm_user = env::var("RABBITMQ_USERNAME")
        .unwrap_or_else(|_| "admin".to_string());
    let rm_pass = env::var("RABBITMQ_PASSWORD")
        .unwrap_or_else(|_| "admin".to_string());
    let status_url = env::var("STATUS_UPDATE_URL")
        .unwrap_or_else(|_| "http://10.2.1.11:8080/api/jobs/status".to_string());
    let orchestrator_url = env::var("STATUS_UPDATE_URL")
        .unwrap_or_else(|_| "http://10.2.1.11:8081".to_string());


    let worker_id = env::var("WORKER_ID")
        .unwrap_or_else(|_| format!("rust-worker-{}", Uuid::new_v4().to_string().chars().take(8).collect::<String>()));
    let worker_capacity = env::var("WORKER_CAPACITY")
        .unwrap_or_else(|_| "10".to_string());

    info!("Starting Rust Worker: {}", worker_id);


    // Initialize State
    let ctx = Arc::new(WorkerContext {
        worker_id: worker_id.clone(),
        worker_type: "rust".to_string(),
        status_url,
        orchestrator_url,
        handlers: vec![
            Box::new(CalculationJobHandler),
            Box::new(TransformationJobHandler)
        ],
        http_client: Client::new(),
        capacity: worker_capacity.trim().parse().unwrap_or(10),
        metrics: Mutex::new(
            WorkerMetrics {
                current_load: 0,
                total_processed: 0,
                successful_jobs: 0,
                failed_jobs: 0
            }
        )
    });

    // Connect to RabbitMQ
    let addr = format!("amqp://{}:{}@{}:{}/%2f", rm_user, rm_pass, rm_host, rm_port);
    let conn = Connection::connect(&addr, ConnectionProperties::default()).await?;
    let channel = conn.create_channel().await?;

    // Set QoS exactly equal to our capacity. This allows RabbitMQ to push up to 'capacity'
    // messages to our local buffer, so we can sort through them quickly.
    channel.basic_qos(ctx.capacity as u16, BasicQosOptions::default()).await?;

    // Declare and Bind all 3 queues
    let queues = vec![("job.high", 10), ("job.medium", 5), ("job.low", 1)];
    for (queue_name, priority) in queues {
        let mut args = FieldTable::default();
        args.insert("x-max-priority".into(), lapin::types::AMQPValue::LongInt(priority));
        channel.queue_declare(queue_name, QueueDeclareOptions { durable: true, ..Default::default() }, args).await?;
        channel.queue_bind(queue_name, "jobs.exchange", queue_name, QueueBindOptions::default(), FieldTable::default()).await?;
    }

    // Create specific consumers for each queue
    let mut consumer_high = channel.basic_consume("job.high", &format!("{}-high", worker_id), BasicConsumeOptions::default(), FieldTable::default()).await?;
    let mut consumer_medium = channel.basic_consume("job.medium", &format!("{}-med", worker_id), BasicConsumeOptions::default(), FieldTable::default()).await?;
    let mut consumer_low = channel.basic_consume("job.low", &format!("{}-low", worker_id), BasicConsumeOptions::default(), FieldTable::default()).await?;

    // Create a Semaphore to strictly limit concurrency to exactly 'capacity'
    let semaphore = Arc::new(Semaphore::new(ctx.capacity as usize));

    info!("Listening with STRICT priority: High -> Medium -> Low");


    let ctx_heartbeat = Arc::clone(&ctx);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
        loop {
            interval.tick().await;
            ctx_heartbeat.send_heartbeat().await;
        }
    });
    info!("Heartbeat loop started (10s interval)");

    // The Single Prioritized Event Loop
    loop {
        // Wait here until we have a free slot (0-'capacity')
        // If 'capacity' tasks are running, this blocks until one finishes!
        let permit = Arc::clone(&semaphore).acquire_owned().await?;

        // Check the queues. 'biased' forces it to check top-to-bottom.
        // It will NEVER pull a medium job if a high job is waiting in the buffer.
        let (delivery_result, queue_name) = tokio::select! {
            biased;
            Some(msg) = consumer_high.next() => (msg, "job.high"),
            Some(msg) = consumer_medium.next() => (msg, "job.medium"),
            Some(msg) = consumer_low.next() => (msg, "job.low"),
        };

        if let Ok(delivery) = delivery_result {
            let ctx_job = Arc::clone(&ctx);
            let channel_job = channel.clone();
            let delivery_tag = delivery.delivery_tag;

            // Spawn the task
            tokio::spawn(async move {
                // When this task finishes and the variable is dropped,
                // it automatically returns the permit to the Semaphore!
                let _permit = permit;

                // --- Update Load ---
                {
                    let mut m = ctx_job.metrics.lock().await;
                    m.current_load += 1;
                }

                let body = std::str::from_utf8(&delivery.data).unwrap_or("{}");

                if let Ok(job) = serde_json::from_str::<Job>(body) {
                    info!("[{}] Pulled from {} priority queue", job.id, queue_name);

                    ctx_job.send_status(&job.id, "running", None, None).await;

                    let mut handled = false;
                    for handler in &ctx_job.handlers {
                        if handler.can_handle(&job.job_type) {
                            info!("Handler {} pick up to handler job with id {}", handler.get_name(), job.id);
                            let result = handler.execute(&job).await;
                            ctx_job.send_status(&job.id, "completed", Some(result), None).await;
                            handled = true;
                            break;
                        }
                    }

                    if !handled {
                        ctx_job.send_status(&job.id, "completed", Some(json!({"echo": "unhandled"})), None).await;
                    }

                    let _ = channel_job.basic_ack(delivery_tag, BasicAckOptions::default()).await;
                } else {
                    let _ = channel_job.basic_nack(delivery_tag, BasicNackOptions { requeue: false, ..Default::default() }).await;
                }

                // --- Decrement Load ---
                {
                    let mut m = ctx_job.metrics.lock().await;
                    m.current_load -= 1;
                    m.total_processed += 1;
                }
                // The task ends here -> _permit is dropped -> Semaphore slot opens up!
            });
        } else {
            // If message fetching failed, we must drop the permit manually so it isn't lost
            drop(permit);
        }
    }
}
