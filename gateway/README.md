# DistriQueue API Gateway

Java/Spring Boot API gateway for DistriQueue. It accepts job requests, persists state in H2, routes jobs to RabbitMQ by priority, communicates with Erlang orchestrators, and streams updates over SSE.

## Deployment Target
- VM host IP: `10.2.1.11`
- Default gateway URL (standard profile): `http://10.2.1.11:8082/api`
- Default gateway URL (`vm` profile): `http://10.2.1.11:8080/api`

## Stack
- Java `25`
- Spring Boot `4.0.2`
- Spring Web, WebFlux, Validation, Data JPA
- RabbitMQ, Redis
- H2 (file DB)
- Springdoc OpenAPI (Swagger UI)
- Micrometer + Prometheus

## Runtime Configuration
Main config files:
- `src/main/resources/application.yaml` (default/local + VM-friendly defaults)
- `src/main/resources/application-vm.properties` (VM profile overrides)
- `src/main/resources/application-docker.yml` (container profile)

Important defaults from `application.yaml`:
- `SERVER_PORT=8082`
- `server.servlet.context-path=/api`
- `RABBITMQ_ADDRESSES=10.2.1.11:5672,10.2.1.12:5672`
- `REDIS_HOST=10.2.1.11`
- `ERLANG_NODES=orchestrator@10.2.1.11,orchestrator@10.2.1.12`
- `ERLANG_REST_PORT=8081`

## API Endpoints
Base path: `/api`

- `POST /jobs`
- `GET /jobs/{id}`
- `GET /jobs`
- `POST /jobs/batch`
- `POST /jobs/{id}/cancel`
- `POST /jobs/{id}/retry`
- `GET /jobs/statistics`
- `GET /jobs/stream` (SSE)

## Run
Prerequisites:
- Java 25
- RabbitMQ reachable from gateway VM
- Redis reachable from gateway VM
- Erlang orchestrator nodes reachable from gateway VM

Start locally/default profile:
```bash
./mvnw spring-boot:run
```

Start with VM profile:
```bash
./mvnw spring-boot:run -Dspring-boot.run.profiles=vm
```

## Package for VM
Build executable jar with VM deployment profile:
```bash
./mvnw clean package -Pvm-deploy
```

Run jar on VM:
```bash
java -jar target/gateway-0.0.1-SNAPSHOT.jar --spring.profiles.active=vm
```

## API Docs and Observability
- Swagger UI: `/api/swagger-ui.html`
- OpenAPI JSON: `/api/v3/api-docs`
- Health: `/api/actuator/health`
- Metrics: `/api/actuator/metrics`
- Prometheus: `/api/actuator/prometheus`

## Storage and Logs
- H2 DB file: `./data/distriqueue`
- App log file: `./logs/gateway.log`

## Test
```bash
./mvnw test
```
