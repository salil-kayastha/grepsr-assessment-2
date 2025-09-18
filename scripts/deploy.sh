#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
NAMESPACE="microservices-app-${ENVIRONMENT}"

echo "🚀 Deploying to ${ENVIRONMENT} environment..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if kustomize is available
if ! command -v kustomize &> /dev/null; then
    echo "❌ kustomize is not installed. Please install kustomize first."
    exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Apply the configuration
echo "📦 Applying Kubernetes manifests..."
kubectl apply -k k8s/overlays/${ENVIRONMENT}

# Wait for deployments to be ready
echo "⏳ Waiting for deployments to be ready..."
kubectl rollout status deployment/db-deployment -n ${NAMESPACE} --timeout=300s
kubectl rollout status deployment/api-deployment -n ${NAMESPACE} --timeout=300s
kubectl rollout status deployment/worker-deployment -n ${NAMESPACE} --timeout=300s
kubectl rollout status deployment/frontend-deployment -n ${NAMESPACE} --timeout=300s

echo "✅ Deployment to ${ENVIRONMENT} completed successfully!"

# Show service information
echo "📋 Service information:"
kubectl get services -n ${NAMESPACE}

# Show pod status
echo "📋 Pod status:"
kubectl get pods -n ${NAMESPACE}

if [ "${ENVIRONMENT}" = "dev" ]; then
    echo "🌐 Access the application:"
    echo "Frontend: http://localhost:30000"
    echo "API: http://localhost:30001/api/health"
fi