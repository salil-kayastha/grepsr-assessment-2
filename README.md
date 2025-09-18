# Microservices Application

A production-ready microservices application with Docker containerization, Kubernetes deployment, and CI/CD pipeline.

## Architecture

This application consists of four main components:

1. **API Service** (Node.js) - REST API that handles business logic and database operations
2. **Worker Service** (Python) - Background job processor that handles asynchronous tasks
3. **Frontend Service** (React) - User interface served via Nginx
4. **Database** (PostgreSQL) - Shared persistent storage for API and Worker services

## Quick Start

### Local Development with Docker Compose

```bash
# Clone the repository
git clone <repository-url>
cd microservices-app

# Start all services
docker-compose up --build

# Access the application
# Frontend: http://localhost:3000
# API: http://localhost:3001/api/health
```

### Local Kubernetes Development

```bash
# Set up local Kubernetes cluster (kind)
./scripts/local-setup.sh

# Deploy to local cluster
./scripts/deploy.sh dev

# Access the application
# Frontend: http://localhost:30000
# API: http://localhost:30001/api/health
```

## Project Structure

```
microservices-app/
├── api-service/           # Node.js REST API
│   ├── src/
│   ├── Dockerfile
│   └── package.json
├── worker-service/        # Python background worker
│   ├── src/
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt
├── frontend-service/      # React frontend
│   ├── src/
│   ├── public/
│   ├── Dockerfile
│   └── package.json
├── k8s/                   # Kubernetes configurations
│   ├── base/             # Base configurations
│   └── overlays/         # Environment-specific configs
├── scripts/              # Deployment and utility scripts
├── .github/workflows/    # CI/CD pipeline
└── docker-compose.yml    # Local development setup
```

## Docker

### Production-Grade Dockerfiles

Each service uses multi-stage builds and follows security best practices:

- **Non-root users** for enhanced security
- **Multi-stage builds** to minimize image size
- **Health checks** for container monitoring
- **Security updates** applied during build
- **Dependency caching** for faster builds

### Building Images

```bash
# Build all services
docker-compose build

# Build individual services
docker build -t api-service ./api-service
docker build -t worker-service ./worker-service
docker build -t frontend-service ./frontend-service
```

## Kubernetes Deployment

### Prerequisites

- kubectl
- kustomize
- Local cluster (kind/minikube) or cloud cluster access

### Deployment Environments

The application supports three environments:

- **Development** (`k8s/overlays/dev/`)
- **Staging** (`k8s/overlays/staging/`)
- **Production** (`k8s/overlays/production/`)

### Manual Deployment

```bash
# Deploy to development
kubectl apply -k k8s/overlays/dev

# Deploy to staging
kubectl apply -k k8s/overlays/staging

# Deploy to production
kubectl apply -k k8s/overlays/production
```

### Automated Deployment

```bash
# Use deployment script
./scripts/deploy.sh dev      # Deploy to development
./scripts/deploy.sh staging  # Deploy to staging
./scripts/deploy.sh production # Deploy to production
```

### Database Persistence Strategy

- **Persistent Volume Claims (PVC)** for database storage
- **5Gi storage** allocated by default
- **ReadWriteOnce** access mode for single-node attachment
- **Automatic backup** (configure based on your cloud provider)

#### Database Configuration

```yaml
# Persistent storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

## CI/CD Pipeline

### GitHub Actions Workflow

The CI/CD pipeline includes:

1. **Testing Phase**
   - Unit tests for all services
   - Code coverage reporting
   - Security scanning

2. **Build Phase**
   - Docker image building
   - Multi-architecture support
   - Image vulnerability scanning

3. **Deploy Phase**
   - Automated deployment to staging/production
   - Rolling updates with zero downtime
   - Health checks and rollback on failure

### Pipeline Triggers

- **Push to main** → Deploy to production
- **Push to develop** → Deploy to staging
- **Pull requests** → Run tests only

### Rollback Mechanism

```bash
# Manual rollback
./scripts/rollback.sh production

# Or via GitHub Actions
# Trigger the rollback workflow manually
```

## Configuration Management

### Environment Variables

Configuration is managed through:

- **ConfigMaps** for non-sensitive data
- **Secrets** for sensitive data (passwords, tokens)
- **Environment-specific overlays** for customization

### Key Configuration

```yaml
# ConfigMap
DB_HOST: db-service
DB_NAME: appdb
DB_PORT: "5432"
API_PORT: "3000"

# Secrets (base64 encoded)
DB_USER: postgres
DB_PASSWORD: password
```

## Monitoring and Observability

### Health Checks

All services include health check endpoints:

- **API Service**: `GET /api/health`
- **Frontend Service**: `GET /` (nginx status)
- **Database**: PostgreSQL `pg_isready`

### Metrics and Monitoring

- **Prometheus** integration ready
- **Custom metrics** endpoints
- **Kubernetes probes** configured
- **Resource monitoring** with requests/limits

### Logging

- **Structured logging** in all services
- **Centralized log collection** ready
- **Log levels** configurable via environment

## Scaling and Performance

### Horizontal Pod Autoscaling

```yaml
# Example HPA configuration
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Resource Management

Each service has defined:
- **Resource requests** for scheduling
- **Resource limits** for protection
- **Quality of Service** classes

## Troubleshooting

### Common Issues

#### Database Connection Issues

```bash
# Check database pod status
kubectl get pods -l app=db -n microservices-dev

# Check database logs
kubectl logs -l app=db -n microservices-dev

# Test database connectivity
kubectl exec -it <api-pod> -n microservices-dev -- nc -zv db-service 5432
```

#### API Service Issues

```bash
# Check API service health
curl http://localhost:30001/api/health

# Check API logs
kubectl logs -l app=api -n microservices-dev

# Check service endpoints
kubectl get endpoints api-service -n microservices-dev
```

#### Frontend Issues

```bash
# Check frontend service
curl http://localhost:30000

# Check nginx configuration
kubectl exec -it <frontend-pod> -n microservices-dev -- cat /etc/nginx/conf.d/default.conf
```

### Performance Issues

#### Database Performance

```bash
# Check database metrics
kubectl exec -it <db-pod> -n microservices-dev -- psql -U postgres -d appdb -c "
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation 
FROM pg_stats 
WHERE schemaname = 'public';"

# Check slow queries
kubectl exec -it <db-pod> -n microservices-dev -- psql -U postgres -d appdb -c "
SELECT query, mean_time, calls 
FROM pg_stat_statements 
ORDER BY mean_time DESC 
LIMIT 10;"
```

#### Application Performance

```bash
# Check resource usage
kubectl top pods -n microservices-dev

# Check HPA status (if configured)
kubectl get hpa -n microservices-dev

# Monitor application metrics
kubectl port-forward svc/prometheus 9090:9090 -n microservices-dev
# Access Prometheus at http://localhost:9090
```

### Debugging Commands

```bash
# Get all resources
kubectl get all -n microservices-dev

# Describe problematic pods
kubectl describe pod <pod-name> -n microservices-dev

# Check events
kubectl get events -n microservices-dev --sort-by='.lastTimestamp'

# Access pod shell
kubectl exec -it <pod-name> -n microservices-dev -- /bin/sh
```

## Security

### Container Security

- Non-root users in all containers
- Minimal base images (Alpine Linux)
- Regular security updates
- No secrets in images

### Kubernetes Security

- Network policies (implement as needed)
- RBAC configuration
- Pod security policies
- Secret management

## Development

### Running Tests

```bash
# API Service tests
cd api-service
npm test

# Frontend tests
cd frontend-service
npm test

# Worker Service tests
cd worker-service
python -m pytest tests/
```

### Local Development

```bash
# Start services for development
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# Or run individual services
cd api-service && npm run dev
cd frontend-service && npm start
cd worker-service && python src/worker.py
```
