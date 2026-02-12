#!/usr/bin/env python3
"""
DistriQueue Python Worker
Complete implementation for distributed job processing system
"""

import pika
import json
import time
import uuid
import threading
import logging
import requests
import socket
import signal
import sys
import os
from typing import Dict, Any, Optional, List, Callable
from datetime import datetime
from queue import Queue
from concurrent.futures import ThreadPoolExecutor, Future
import traceback

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class JobHandler:
    """Base class for job handlers"""

    def can_handle(self, job_type: str) -> bool:
        """Check if this handler can process the job type"""
        return False

    def execute(self, job: Dict[str, Any]) -> Dict[str, Any]:
        """Execute the job"""
        raise NotImplementedError

    def get_name(self) -> str:
        """Get handler name"""
        return self.__class__.__name__


class CalculationJobHandler(JobHandler):
    """Handler for calculation jobs"""

    def can_handle(self, job_type: str) -> bool:
        return job_type in ['calculate', 'sum', 'average', 'min', 'max', 'sort', 'aggregate']

    def execute(self, job: Dict[str, Any]) -> Dict[str, Any]:
        payload = job.get('payload', {})
        operation = payload.get('operation', 'sum')
        numbers = payload.get('numbers', [])

        if not numbers:
            # Generate random numbers if none provided
            import random
            count = payload.get('count', 100)
            numbers = [random.randint(1, 1000) for _ in range(count)]

        result = {}
        start_time = time.time()

        if operation == 'sum':
            result = {'sum': sum(numbers), 'count': len(numbers)}
        elif operation == 'average':
            result = {'average': sum(numbers) / len(numbers) if numbers else 0, 'count': len(numbers)}
        elif operation == 'min':
            result = {'min': min(numbers) if numbers else 0}
        elif operation == 'max':
            result = {'max': max(numbers) if numbers else 0}
        elif operation == 'sort':
            result = {'sorted': sorted(numbers), 'original': numbers[:10]}  # First 10 only
        elif operation == 'aggregate':
            result = {
                'sum': sum(numbers),
                'average': sum(numbers) / len(numbers) if numbers else 0,
                'min': min(numbers) if numbers else 0,
                'max': max(numbers) if numbers else 0,
                'count': len(numbers)
            }
        elif operation == 'statistics':
            import statistics
            result = {
                'mean': statistics.mean(numbers) if numbers else 0,
                'median': statistics.median(numbers) if numbers else 0,
                'stdev': statistics.stdev(numbers) if len(numbers) > 1 else 0,
                'variance': statistics.variance(numbers) if len(numbers) > 1 else 0
            }

        # Simulate processing time based on data size
        processing_time = min(5.0, len(numbers) * 0.01)
        time.sleep(processing_time)

        result['processing_time_ms'] = int((time.time() - start_time) * 1000)
        return result

    def get_name(self) -> str:
        return "CalculationJobHandler"


class TransformationJobHandler(JobHandler):
    """Handler for data transformation jobs"""

    def can_handle(self, job_type: str) -> bool:
        return job_type in ['transform', 'uppercase', 'lowercase', 'reverse', 'filter', 'normalize']

    def execute(self, job: Dict[str, Any]) -> Dict[str, Any]:
        payload = job.get('payload', {})
        operation = payload.get('operation', 'uppercase')
        data = payload.get('data', {})

        result = {}
        start_time = time.time()

        if operation == 'uppercase':
            transformed = {k.upper(): str(v).upper() for k, v in data.items()}
            result = {'transformed': transformed, 'operation': 'uppercase'}
        elif operation == 'lowercase':
            transformed = {k.lower(): str(v).lower() for k, v in data.items()}
            result = {'transformed': transformed, 'operation': 'lowercase'}
        elif operation == 'reverse':
            transformed = {
                k[::-1]: str(v)[::-1] for k, v in data.items()
            }
            result = {'transformed': transformed, 'operation': 'reverse'}
        elif operation == 'filter':
            filter_key = payload.get('filter_key')
            filter_value = payload.get('filter_value')

            if filter_key and filter_value:
                filtered = {k: v for k, v in data.items()
                            if filter_key in str(k) or filter_value in str(v)}
            else:
                # Filter numeric values > 0
                filtered = {k: v for k, v in data.items()
                            if isinstance(v, (int, float)) and v > 0}

            result = {
                'filtered': filtered,
                'original_count': len(data),
                'filtered_count': len(filtered)
            }
        elif operation == 'normalize':
            # Normalize numeric values to 0-1 range
            numeric_values = [v for v in data.values() if isinstance(v, (int, float))]
            if numeric_values:
                min_val = min(numeric_values)
                max_val = max(numeric_values)
                range_val = max_val - min_val if max_val > min_val else 1

                normalized = {
                    k: (v - min_val) / range_val if isinstance(v, (int, float)) else v
                    for k, v in data.items()
                }
                result = {
                    'normalized': normalized,
                    'min': min_val,
                    'max': max_val
                }

        # Simulate processing time
        time.sleep(min(2.0, len(data) * 0.05))

        result['processing_time_ms'] = int((time.time() - start_time) * 1000)
        return result

    def get_name(self) -> str:
        return "TransformationJobHandler"


class ValidationJobHandler(JobHandler):
    """Handler for validation jobs"""

    def can_handle(self, job_type: str) -> bool:
        return job_type in ['validate', 'email', 'phone', 'numeric', 'required', 'range', 'length', 'regex']

    def execute(self, job: Dict[str, Any]) -> Dict[str, Any]:
        payload = job.get('payload', {})
        validation_type = payload.get('type', 'generic')
        value = payload.get('value', '')

        import re
        result = {}
        start_time = time.time()

        if validation_type == 'email':
            pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
            is_valid = bool(re.match(pattern, str(value)))
            result = {
                'valid': is_valid,
                'type': 'email',
                'value': value
            }
        elif validation_type == 'phone':
            # Simple phone validation
            pattern = r'^\+?[1-9]\d{1,14}$'
            is_valid = bool(re.match(pattern, re.sub(r'[\s\-\(\)]', '', str(value))))
            result = {
                'valid': is_valid,
                'type': 'phone',
                'value': value
            }
        elif validation_type == 'numeric':
            try:
                float(value)
                is_valid = True
            except (ValueError, TypeError):
                is_valid = False
            result = {
                'valid': is_valid,
                'type': 'numeric',
                'value': value
            }
        elif validation_type == 'required':
            is_valid = value is not None and str(value).strip() != ''
            result = {
                'valid': is_valid,
                'type': 'required',
                'value': value
            }
        elif validation_type == 'range':
            min_val = float(payload.get('min', 0))
            max_val = float(payload.get('max', 100))
            try:
                num_val = float(value)
                is_valid = min_val <= num_val <= max_val
            except (ValueError, TypeError):
                is_valid = False
            result = {
                'valid': is_valid,
                'type': 'range',
                'min': min_val,
                'max': max_val,
                'value': value
            }
        elif validation_type == 'length':
            min_len = int(payload.get('min_length', 0))
            max_len = int(payload.get('max_length', 255))
            str_val = str(value)
            is_valid = min_len <= len(str_val) <= max_len
            result = {
                'valid': is_valid,
                'type': 'length',
                'min_length': min_len,
                'max_length': max_len,
                'length': len(str_val),
                'value': value
            }
        elif validation_type == 'regex':
            pattern = payload.get('pattern', '')
            try:
                is_valid = bool(re.match(pattern, str(value)))
            except re.error:
                is_valid = False
            result = {
                'valid': is_valid,
                'type': 'regex',
                'pattern': pattern,
                'value': value
            }
        else:
            # Generic validation - check if not empty
            is_valid = value is not None and str(value).strip() != ''
            result = {
                'valid': is_valid,
                'type': 'generic',
                'value': value
            }

        # Simulate validation time
        time.sleep(0.2)

        result['processing_time_ms'] = int((time.time() - start_time) * 1000)
        return result

    def get_name(self) -> str:
        return "ValidationJobHandler"


class PythonWorker:
    """Enhanced Python Worker for DistriQueue"""

    def __init__(self,
                 rabbitmq_host: str = 'rabbitmq1',
                 rabbitmq_port: int = 5672,
                 rabbitmq_user: str = 'admin',
                 rabbitmq_pass: str = 'admin',
                 worker_id: Optional[str] = None,
                 worker_type: str = 'python',
                 capacity: int = 10,
                 orchestrator_url: Optional[str] = None,
                 status_update_url: Optional[str] = None):

        self.worker_id = worker_id or f"python-worker-{uuid.uuid4().hex[:8]}"
        self.worker_type = worker_type
        self.capacity = capacity
        self.current_load = 0
        self.total_jobs_processed = 0
        self.successful_jobs = 0
        self.failed_jobs = 0

        # RabbitMQ configuration
        self.rabbitmq_host = rabbitmq_host
        self.rabbitmq_port = rabbitmq_port
        self.rabbitmq_user = rabbitmq_user
        self.rabbitmq_pass = rabbitmq_pass

        # Queue configuration
        self.queues = {
            'high': 'job.high',
            'medium': 'job.medium',
            'low': 'job.low'
        }

        # API endpoints
        self.orchestrator_url = orchestrator_url or os.getenv('ORCHESTRATOR_URL', 'http://orchestrator1:8081')
        self.status_update_url = status_update_url or os.getenv('STATUS_UPDATE_URL',
                                                                'http://api-gateway:8080/api/v1/jobs/status')

        # Connection state
        self.connection = None
        self.channel = None
        self.running = False

        # Job handlers
        self.handlers: List[JobHandler] = [
            CalculationJobHandler(),
            TransformationJobHandler(),
            ValidationJobHandler()
        ]

        # Threading
        self.executor = ThreadPoolExecutor(max_workers=capacity)
        self.heartbeat_thread = None
        self.metrics_thread = None
        self.futures: Dict[str, Future] = {}

        # Metrics
        self.start_time = time.time()
        self.job_times: List[float] = []

        logger.info(f"Initialized worker {self.worker_id} (type: {worker_type}, capacity: {capacity})")

    def connect(self) -> None:
        """Establish connection to RabbitMQ with retry logic"""
        retries = 5
        retry_delay = 5

        for attempt in range(retries):
            try:
                credentials = pika.PlainCredentials(self.rabbitmq_user, self.rabbitmq_pass)
                parameters = pika.ConnectionParameters(
                    host=self.rabbitmq_host,
                    port=self.rabbitmq_port,
                    credentials=credentials,
                    heartbeat=600,
                    blocked_connection_timeout=300,
                    connection_attempts=3,
                    retry_delay=1
                )

                self.connection = pika.BlockingConnection(parameters)
                self.channel = self.connection.channel()

                # Declare exchanges and queues
                self._setup_rabbitmq()

                logger.info(
                    f"Worker {self.worker_id} connected to RabbitMQ at {self.rabbitmq_host}:{self.rabbitmq_port}")
                return

            except Exception as e:
                logger.error(f"Connection attempt {attempt + 1}/{retries} failed: {e}")
                if attempt < retries - 1:
                    time.sleep(retry_delay)
                else:
                    raise

    def _setup_rabbitmq(self) -> None:
        """Setup RabbitMQ exchanges, queues, and bindings"""
        # Declare exchange
        self.channel.exchange_declare(
            exchange='jobs.exchange',
            exchange_type='direct',
            durable=True
        )

        # Declare queues with priorities and dead letter configuration
        for priority, queue_name in self.queues.items():
            args = {
                'x-max-priority': 10 if priority == 'high' else 5 if priority == 'medium' else 1,
                'x-dead-letter-exchange': '',
                'x-dead-letter-routing-key': 'job.dead-letter',
                'x-queue-type': 'classic'
            }

            self.channel.queue_declare(
                queue=queue_name,
                durable=True,
                arguments=args
            )

            # Bind queue to exchange
            self.channel.queue_bind(
                queue=queue_name,
                exchange='jobs.exchange',
                routing_key=queue_name
            )

        # Declare dead letter queue
        self.channel.queue_declare(
            queue='job.dead-letter',
            durable=True
        )

        logger.debug("RabbitMQ setup completed")

    def find_handler(self, job_type: str) -> Optional[JobHandler]:
        """Find appropriate handler for job type"""
        for handler in self.handlers:
            if handler.can_handle(job_type):
                return handler
        return None

    def process_job(self, ch, method, properties, body) -> None:
        """Process a job from the queue"""
        job_start_time = time.time()

        try:
            job = json.loads(body)
            job_id = job.get('id')
            job_type = job.get('type', 'default')

            # Update load
            self.current_load += 1

            logger.info(f"[{job_id}] Processing {job_type} job")

            # Send running status
            self.send_status_update(job_id, 'running', progress=0)

            # Find appropriate handler
            handler = self.find_handler(job_type)

            if handler:
                logger.debug(f"[{job_id}] Using handler: {handler.get_name()}")
                result = handler.execute(job)

                # Send progress updates for long-running jobs
                if 'progress' in result:
                    self.send_status_update(job_id, 'running',
                                            progress=result['progress'],
                                            result=result)

                # Mark as completed
                self.send_status_update(job_id, 'completed', result=result)

                logger.info(f"[{job_id}] Job completed successfully")
                self.successful_jobs += 1

            else:
                # No handler found - use default processing
                logger.warning(f"[{job_id}] No handler found for type: {job_type}, using default")
                result = self._default_processing(job)
                self.send_status_update(job_id, 'completed', result=result)
                self.successful_jobs += 1

            # Acknowledge message
            ch.basic_ack(delivery_tag=method.delivery_tag)

            # Update metrics
            self.total_jobs_processed += 1
            job_time = time.time() - job_start_time
            self.job_times.append(job_time)

            # Keep only last 100 job times
            if len(self.job_times) > 100:
                self.job_times.pop(0)

        except Exception as e:
            logger.error(f"Failed to process job: {e}\n{traceback.format_exc()}")
            self.failed_jobs += 1

            # Send failure status
            job_id = job.get('id') if 'job' in locals() else 'unknown'
            self.send_status_update(job_id, 'failed', error=str(e))

            # Check if job should be retried
            retry_count = job.get('retry_count', 0) if 'job' in locals() else 0
            max_retries = job.get('max_retries', 3) if 'job' in locals() else 3

            if retry_count < max_retries:
                # Increment retry count and requeue
                job['retry_count'] = retry_count + 1
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
                logger.info(f"[{job_id}] Requeued for retry ({retry_count + 1}/{max_retries})")
            else:
                # Max retries exceeded, send to dead letter
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
                logger.error(f"[{job_id}] Max retries ({max_retries}) exceeded")

        finally:
            # Update load
            self.current_load -= 1

    def _default_processing(self, job: Dict[str, Any]) -> Dict[str, Any]:
        """Default job processing when no handler matches"""
        time.sleep(1)  # Simulate work
        return {
            'echo': job.get('payload', {}),
            'processed_by': self.worker_id,
            'timestamp': datetime.utcnow().isoformat()
        }

    def send_status_update(self, job_id: str, status: str,
                           result: Optional[Dict] = None,
                           error: Optional[str] = None,
                           progress: Optional[int] = None) -> bool:
        """Send job status update to orchestrator/API"""
        try:
            status_update = {
                'jobId': job_id,
                'status': status,
                'workerId': self.worker_id,
                'timestamp': datetime.utcnow().isoformat()
            }

            if result:
                status_update['result'] = result
            if error:
                status_update['errorMessage'] = error
            if progress is not None:
                status_update['progress'] = progress

            response = requests.post(
                self.status_update_url,
                json=status_update,
                headers={'Content-Type': 'application/json'},
                timeout=5
            )

            if response.status_code in [200, 202]:
                logger.debug(f"[{job_id}] Status update sent: {status}")
                return True
            else:
                logger.warning(f"[{job_id}] Status update failed: {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"[{job_id}] Failed to send status update: {e}")
            return False

    def send_heartbeat(self) -> bool:
        """Send heartbeat to orchestrator"""
        try:
            heartbeat = {
                'worker_id': self.worker_id,
                'worker_type': self.worker_type,
                'capacity': self.capacity,
                'current_load': self.current_load,
                'total_jobs_processed': self.total_jobs_processed,
                'successful_jobs': self.successful_jobs,
                'failed_jobs': self.failed_jobs,
                'timestamp': int(time.time() * 1000)
            }

            response = requests.post(
                f"{self.orchestrator_url}/api/workers/heartbeat",
                json=heartbeat,
                headers={'Content-Type': 'application/json'},
                timeout=5
            )

            if response.status_code == 200:
                logger.debug(f"Heartbeat sent, load: {self.current_load}/{self.capacity}")
                return True
            else:
                logger.warning(f"Heartbeat failed: {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"Heartbeat failed: {e}")
            return False

    def heartbeat_loop(self) -> None:
        """Periodic heartbeat sending"""
        while self.running:
            self.send_heartbeat()

            # Sleep for heartbeat interval (10 seconds)
            for _ in range(10):
                if not self.running:
                    break
                time.sleep(1)

    def metrics_loop(self) -> None:
        """Periodic metrics logging"""
        while self.running:
            avg_time = sum(self.job_times) / len(self.job_times) if self.job_times else 0
            success_rate = (
                        self.successful_jobs / self.total_jobs_processed * 100) if self.total_jobs_processed > 0 else 0

            logger.info(f"Metrics - Load: {self.current_load}/{self.capacity}, "
                        f"Processed: {self.total_jobs_processed}, "
                        f"Success Rate: {success_rate:.1f}%, "
                        f"Avg Time: {avg_time:.2f}s")

            # Sleep for metrics interval (30 seconds)
            for _ in range(30):
                if not self.running:
                    break
                time.sleep(1)

    def start_consuming(self) -> None:
        """Start consuming jobs from queues"""
        # Set QoS to control prefetch count
        self.channel.basic_qos(prefetch_count=1)

        # Consume from all queues
        for queue_name in self.queues.values():
            self.channel.basic_consume(
                queue=queue_name,
                on_message_callback=self.process_job,
                consumer_tag=f"{self.worker_id}-{queue_name}"
            )

        self.running = True
        logger.info(f"Worker {self.worker_id} started consuming from queues")

        # Start heartbeat thread
        self.heartbeat_thread = threading.Thread(target=self.heartbeat_loop, daemon=True)
        self.heartbeat_thread.start()

        # Start metrics thread
        self.metrics_thread = threading.Thread(target=self.metrics_loop, daemon=True)
        self.metrics_thread.start()

        # Register signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

        try:
            self.channel.start_consuming()
        except Exception as e:
            logger.error(f"Consumer error: {e}")
        finally:
            self.stop()

    def signal_handler(self, signum, frame) -> None:
        """Handle shutdown signals"""
        logger.info(f"Received signal {signum}, shutting down...")
        self.stop()
        sys.exit(0)

    def start(self) -> None:
        """Start the worker"""
        try:
            # Send initial registration
            self.connect()
            self.send_heartbeat()
            self.start_consuming()

        except Exception as e:
            logger.error(f"Failed to start worker: {e}")
            self.stop()
            raise

    def stop(self) -> None:
        """Stop the worker gracefully"""
        logger.info(f"Stopping worker {self.worker_id}...")

        self.running = False

        # Wait for current jobs to complete (max 30 seconds)
        if self.current_load > 0:
            logger.info(f"Waiting for {self.current_load} jobs to complete...")
            wait_start = time.time()
            while self.current_load > 0 and time.time() - wait_start < 30:
                time.sleep(1)

        # Stop consuming
        if self.channel and self.channel.is_open:
            try:
                self.channel.stop_consuming()
            except:
                pass

        # Close connection
        if self.connection and self.connection.is_open:
            try:
                self.connection.close()
            except:
                pass

        # Shutdown thread pool
        self.executor.shutdown(wait=True)

        # Send final heartbeat with zero load
        self.current_load = 0
        self.send_heartbeat()

        logger.info(f"Worker {self.worker_id} stopped. "
                    f"Processed: {self.total_jobs_processed}, "
                    f"Success: {self.successful_jobs}, "
                    f"Failed: {self.failed_jobs}")

    def get_status(self) -> Dict[str, Any]:
        """Get worker status"""
        uptime = time.time() - self.start_time
        avg_time = sum(self.job_times) / len(self.job_times) if self.job_times else 0
        success_rate = (self.successful_jobs / self.total_jobs_processed * 100) if self.total_jobs_processed > 0 else 0

        return {
            'worker_id': self.worker_id,
            'worker_type': self.worker_type,
            'status': 'running' if self.running else 'stopped',
            'capacity': self.capacity,
            'current_load': self.current_load,
            'utilization': (self.current_load / self.capacity * 100) if self.capacity > 0 else 0,
            'total_jobs_processed': self.total_jobs_processed,
            'successful_jobs': self.successful_jobs,
            'failed_jobs': self.failed_jobs,
            'success_rate': success_rate,
            'average_processing_time': avg_time,
            'uptime_seconds': uptime,
            'start_time': datetime.fromtimestamp(self.start_time).isoformat()
        }


def main():
    """Main entry point"""
    # Get configuration from environment variables
    rabbitmq_host = os.getenv('RABBITMQ_HOST', 'rabbitmq1')
    rabbitmq_port = int(os.getenv('RABBITMQ_PORT', '5672'))
    rabbitmq_user = os.getenv('RABBITMQ_USERNAME', 'admin')
    rabbitmq_pass = os.getenv('RABBITMQ_PASSWORD', 'admin')

    worker_id = os.getenv('WORKER_ID')
    worker_type = os.getenv('WORKER_TYPE', 'python')
    capacity = int(os.getenv('WORKER_CAPACITY', '10'))

    orchestrator_url = os.getenv('ORCHESTRATOR_URL', 'http://orchestrator1:8081')
    status_update_url = os.getenv('STATUS_UPDATE_URL', 'http://api-gateway:8080/api/v1/jobs/status')

    # Create and start worker
    worker = PythonWorker(
        rabbitmq_host=rabbitmq_host,
        rabbitmq_port=rabbitmq_port,
        rabbitmq_user=rabbitmq_user,
        rabbitmq_pass=rabbitmq_pass,
        worker_id=worker_id,
        worker_type=worker_type,
        capacity=capacity,
        orchestrator_url=orchestrator_url,
        status_update_url=status_update_url
    )

    try:
        worker.start()
    except KeyboardInterrupt:
        worker.stop()
    except Exception as e:
        logger.error(f"Worker failed: {e}\n{traceback.format_exc()}")
        worker.stop()
        sys.exit(1)


if __name__ == "__main__":
    main()
