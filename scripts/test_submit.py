# scripts/test_submit.py
import requests
import json
import time
import random
from concurrent.futures import ThreadPoolExecutor

API_URL = "http://localhost:8080/api/jobs"


def submit_job(job_type, priority="medium"):
    """Submit a test job to the system"""
    job = {
        "type": job_type,
        "priority": priority,
        "payload": {
            "numbers": [random.randint(1, 100) for _ in range(10)],
            "timestamp": time.time()
        }
    }

    try:
        response = requests.post(API_URL, json=job)
        if response.status_code == 202:
            job_data = response.json()
            print(f"Submitted job: {job_data['id']} ({priority} priority)")
            return job_data['id']
        else:
            print(f"Failed to submit job: {response.status_code}")
            return None
    except Exception as e:
        print(f"Error submitting job: {e}")
        return None


def get_job_status(job_id):
    """Check job status"""
    try:
        response = requests.get(f"{API_URL}/{job_id}")
        if response.status_code == 200:
            return response.json()['status']
        return "unknown"
    except:
        return "error"


def load_test(num_jobs=100):
    """Submit multiple jobs concurrently"""
    priorities = ["high", "medium", "low"]
    job_types = ["calculate", "transform", "validate"]

    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = []
        for i in range(num_jobs):
            priority = random.choice(priorities)
            job_type = random.choice(job_types)
            futures.append(
                executor.submit(submit_job, job_type, priority)
            )

        job_ids = [f.result() for f in futures if f.result()]

    print(f"\nSubmitted {len(job_ids)} jobs")
    return job_ids


def monitor_jobs(job_ids, duration=60):
    """Monitor job completion"""
    print(f"\nMonitoring jobs for {duration} seconds...")
    start_time = time.time()

    while time.time() - start_time < duration:
        completed = 0
        pending = 0
        running = 0
        failed = 0

        for job_id in job_ids:
            status = get_job_status(job_id)
            if status == "completed":
                completed += 1
            elif status == "pending":
                pending += 1
            elif status == "running":
                running += 1
            elif status == "failed":
                failed += 1

        print(f"\rStatus: {completed} completed, {running} running, "
              f"{pending} pending, {failed} failed", end="")
        time.sleep(2)

    print("\nMonitoring completed")


if __name__ == "__main__":
    # Test single job submission
    print("=== Testing Single Job Submission ===")
    job_id = submit_job("calculate", "high")
    if job_id:
        time.sleep(5)
        status = get_job_status(job_id)
        print(f"Job {job_id} status: {status}")

    # Load test
    print("\n=== Load Testing ===")
    job_ids = load_test(num_jobs=50)

    # Monitor progress
    monitor_jobs(job_ids, duration=120)
