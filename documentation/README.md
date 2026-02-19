# TaskForce (Distriqueue)

TaskForce is a distributed job scheduling system built to process complex, heterogeneous tasks across a polyglot cluster. It’s designed as an end-to-end demonstration of core distributed systems concepts: consensus, coordination, message-driven architecture, and fault tolerance.

## What it does

TaskForce implements a complete job scheduling pipeline that supports:

- **Concurrent job submissions** (asynchronous, scalable intake)
- **Reliable execution semantics** (jobs are processed predictably even under load)
- **Automatic recovery from node failures** (fault tolerance / failover)
- **Horizontal scalability** (add nodes to increase throughput)
- **Polyglot execution** (workers can be implemented in multiple languages)

## Architecture (high level)

- **Erlang/OTP Orchestrator**  
  Coordinator responsible for cluster control and scheduling logic, featuring **Raft-based leader election** and **CRDTs for state management**.

- **RabbitMQ Cluster (AMQP)**  
  Message-oriented middleware enabling reliable, priority-based, asynchronous queuing.

- **Java Spring Boot API Gateway**  
  Web-facing entry point providing **REST endpoints** and real-time updates via **Server-Sent Events (SSE)**.

- **Polyglot Worker Farm**  
  Heterogeneous worker nodes, with support for **Python** and **Java** worker implementations.

- **Multi-node deployment**  
  Distributed deployment across multiple Ubuntu VMs with automatic failover.

## Why it exists

Distributed applications often need a job processing system that can coordinate across multiple nodes while remaining consistent and available. TaskForce focuses on the classic scheduling challenges:

- coordination and distributed state
- communication via reliable messaging
- fault tolerance and recovery
- load balancing and scalability

## Repository

Source code (orchestrator, API gateway, workers, and deployment scripts) is available here:

- https://github.com/adrienKoumgangT/distriqueue

## Status

This project is intended as an educational, end-to-end distributed scheduler implementation demonstrating practical distributed systems techniques in a real, multi-component system.

