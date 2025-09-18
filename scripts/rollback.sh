#!/bin/bash

set -e

ENVIRONMENT=${1:-production}
NAMESPACE="microservices-app-${ENVIRONMENT}"

echo "🔄 Rolling back deployments in ${ENVIRONMENT} environment..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Rollback deployments
echo "⏪ Rolling back API deployment..."
kubectl rollout undo deployment/api-deployment -n ${NAMESPACE}

echo "⏪ Rolling back Worker deployment..."
kubectl rollout undo deployment/worker-deployment -n ${NAMESPACE}

echo "⏪ Rolling back Frontend deployment..."
kubectl rollout undo deployment/frontend-deployment -n ${NAMESPACE}

# Wait for rollback to complete
echo "⏳ Waiting for rollback to complete..."
kubectl rollout status deployment/api-deployment -n ${NAMESPACE} --timeout=300s
kubectl rollout status deployment/worker-deployment -n ${NAMESPACE} --timeout=300s
kubectl rollout status deployment/frontend-deployment -n ${NAMESPACE} --timeout=300s

echo "✅ Rollback completed successfully!"

# Show pod status
echo "📋 Pod status after rollback:"
kubectl get pods -n ${NAMESPACE}