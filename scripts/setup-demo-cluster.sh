#!/bin/bash

################################################################################
# Kubernetes Cluster Discovery Tool - Demo Setup
# Creates realistic cluster with Istio, HPAs, PDBs, and various workloads
# Supports: Docker (Linux/Mac/Windows) and QEMU (Mac including M1/M2/M3)
# Works with: AKS, EKS, GKE, minikube, kind, k3s, and any Kubernetes cluster
################################################################################

set -e

echo "=========================================================================="
echo "  Kubernetes Cluster Discovery - Demo Setup"
echo "=========================================================================="
echo ""

# Get cluster name from argument or prompt
if [ -n "$1" ]; then
    CLUSTER_NAME="$1"
    echo "Using cluster name: $CLUSTER_NAME"
else
    read -p "Enter cluster name (default: opscart): " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-opscart}
fi

echo "Cluster name: $CLUSTER_NAME"
echo ""

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Darwin*)    PLATFORM=Mac;;
    Linux*)     PLATFORM=Linux;;
    CYGWIN*|MINGW*|MSYS*) PLATFORM=Windows;;
    *)          PLATFORM="UNKNOWN"
esac

echo "Detected platform: $PLATFORM"
echo ""

# Prompt for driver selection on Mac
if [ "$PLATFORM" = "Mac" ]; then
    echo "Select minikube driver:"
    echo "1) Docker (default, recommended if available)"
    echo "2) QEMU (for Mac without Docker license, supports M1/M2/M3 ARM)"
    echo ""
    read -p "Enter choice [1-2] (default: 1): " DRIVER_CHOICE
    DRIVER_CHOICE=${DRIVER_CHOICE:-1}
    
    if [ "$DRIVER_CHOICE" = "2" ]; then
        DRIVER="qemu"
        CPUS=4
        MEMORY=6144
        echo "Using QEMU driver (ARM-compatible) with reduced resources"
    else
        DRIVER="docker"
        CPUS=4
        MEMORY=8192
        echo "Using Docker driver"
    fi
else
    DRIVER="docker"
    CPUS=4
    MEMORY=8192
fi

echo ""

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "ERROR: minikube not found."
    echo ""
    if [ "$PLATFORM" = "Mac" ]; then
        echo "Install with: brew install minikube"
    elif [ "$PLATFORM" = "Linux" ]; then
        echo "Install with: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
        echo "              sudo install minikube-linux-amd64 /usr/local/bin/minikube"
    fi
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found."
    echo ""
    if [ "$PLATFORM" = "Mac" ]; then
        echo "Install with: brew install kubectl"
    elif [ "$PLATFORM" = "Linux" ]; then
        echo "Install with: curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        echo "              sudo install kubectl /usr/local/bin/kubectl"
    fi
    exit 1
fi

# Cleanup any existing cluster with this name
echo "Checking for existing cluster: $CLUSTER_NAME..."
minikube delete --profile=$CLUSTER_NAME 2>/dev/null || echo "No existing cluster found"
echo ""

# Start minikube with specified profile name
echo "Starting minikube cluster (profile: $CLUSTER_NAME)..."
echo "Driver: $DRIVER | CPUs: $CPUS | Memory: ${MEMORY}MB"
echo "This may take 3-5 minutes on first run..."
echo ""

if [ "$DRIVER" = "qemu" ]; then
    minikube start \
      --profile=$CLUSTER_NAME \
      --driver=qemu \
      --cpus=$CPUS \
      --memory=$MEMORY \
      --disk-size=20g \
      --kubernetes-version=v1.28.0 \
      --network=user
else
    minikube start \
      --profile=$CLUSTER_NAME \
      --nodes 3 \
      --cpus=$CPUS \
      --memory=$MEMORY \
      --driver=$DRIVER \
      --kubernetes-version=v1.28.0
fi

echo ""
echo "Minikube cluster created with profile: $CLUSTER_NAME"
echo ""

# IMPORTANT: Minikube creates context as profile name, ensure it matches
echo "Setting up kubectl context..."
kubectl config use-context $CLUSTER_NAME

echo "Cluster name: $CLUSTER_NAME"
echo "Context name: $(kubectl config current-context)"
echo ""

# Wait for cluster to be fully ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo ""

# Enable metrics-server for HPA
echo "Enabling metrics-server..."
minikube addons enable metrics-server --profile=$CLUSTER_NAME

# Wait for metrics-server
echo "Waiting for metrics-server to be ready..."
sleep 10
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=180s 2>/dev/null || \
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metrics-server -n kube-system --timeout=180s 2>/dev/null || \
echo "  Note: metrics-server may still be starting (will be ready in ~30 seconds)"
echo "Metrics-server enabled"
echo ""

# Install Istio
echo "Installing Istio (minimal profile)..."

# Download Istio if not present
if [ ! -d "istio-1.19.0" ]; then
  echo "Downloading Istio 1.19.0..."
  curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.19.0 sh -
fi

cd istio-1.19.0
export PATH=$PWD/bin:$PATH

# Install Istio with minimal profile
echo "Installing Istio components..."
istioctl install --set profile=minimal -y

cd ..

echo "Istio installed successfully"
echo ""

# Create namespaces
echo "Creating namespaces..."

namespaces=(
  "production"
  "staging"
  "development"
  "monitoring"
  "build-agents"
  "data-processing"
  "kubernetes-dashboard"
)

for ns in "${namespaces[@]}"; do
  kubectl create namespace $ns 2>/dev/null || true
  echo "  Created namespace: $ns"
done

# Label namespaces for Istio injection
kubectl label namespace production istio-injection=enabled --overwrite
kubectl label namespace staging istio-injection=enabled --overwrite
kubectl label namespace development istio-injection=enabled --overwrite

echo "Namespaces created and labeled"
echo ""

# Deploy workloads
echo "Deploying workloads (this will take 2-3 minutes)..."

## Production namespace
echo "  Deploying production workloads..."

# Frontend application with HPA and PDB
kubectl create deployment frontend \
  --image=nginx:latest \
  --replicas=3 \
  -n production 2>/dev/null || true

kubectl set resources deployment frontend \
  --limits=cpu=200m,memory=256Mi \
  --requests=cpu=100m,memory=128Mi \
  -n production 2>/dev/null || true

# Create HPA
kubectl autoscale deployment frontend \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n production 2>/dev/null || true

# Create PDB
cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: frontend
EOF

# Backend API
kubectl create deployment backend-api \
  --image=httpd:latest \
  --replicas=2 \
  -n production 2>/dev/null || true

kubectl set resources deployment backend-api \
  --limits=cpu=300m,memory=512Mi \
  --requests=cpu=150m,memory=256Mi \
  -n production 2>/dev/null || true

# Database (StatefulSet)
cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: v1
kind: Service
metadata:
  name: database
  namespace: production
spec:
  clusterIP: None
  selector:
    app: database
  ports:
  - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: database
  namespace: production
spec:
  serviceName: database
  replicas: 2
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: postgres
        image: postgres:14
        env:
        - name: POSTGRES_PASSWORD
          value: demo123
        ports:
        - containerPort: 5432
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
EOF

# Redis cache
kubectl create deployment cache \
  --image=redis:latest \
  --replicas=1 \
  -n production 2>/dev/null || true

# Worker pods
kubectl create deployment worker \
  --image=busybox:latest \
  --replicas=4 \
  -n production \
  -- sh -c "while true; do echo 'Processing...'; sleep 30; done" 2>/dev/null || true

## Staging namespace
echo "  Deploying staging workloads..."

kubectl create deployment frontend \
  --image=nginx:latest \
  --replicas=2 \
  -n staging 2>/dev/null || true

kubectl create deployment backend-api \
  --image=httpd:latest \
  --replicas=1 \
  -n staging 2>/dev/null || true

## Development namespace
echo "  Deploying development workloads..."

kubectl create deployment test-app \
  --image=nginx:latest \
  --replicas=1 \
  -n development 2>/dev/null || true

# Create a failing pod for demonstration
kubectl run failing-pod \
  --image=invalid-image-that-does-not-exist \
  -n development 2>/dev/null || true

## Build agents (StatefulSet)
echo "  Deploying build agents..."

cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: build-agent
  namespace: build-agents
spec:
  serviceName: build-agent
  replicas: 2
  selector:
    matchLabels:
      app: build-agent
  template:
    metadata:
      labels:
        app: build-agent
    spec:
      containers:
      - name: agent
        image: ubuntu:latest
        command: ["sh", "-c", "while true; do echo 'Building...'; sleep 60; done"]
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "100m"
EOF

## Monitoring namespace
echo "  Deploying monitoring workloads..."

kubectl create deployment prometheus \
  --image=prom/prometheus:latest \
  --replicas=1 \
  -n monitoring 2>/dev/null || true

kubectl create deployment grafana \
  --image=grafana/grafana:latest \
  --replicas=1 \
  -n monitoring 2>/dev/null || true

## Data processing (CronJobs)
echo "  Deploying data processing jobs..."

cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: batch/v1
kind: CronJob
metadata:
  name: data-sync
  namespace: data-processing
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sync
            image: busybox:latest
            command: ["sh", "-c", "echo 'Syncing data...'; sleep 10"]
          restartPolicy: OnFailure
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
  namespace: data-processing
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: busybox:latest
            command: ["sh", "-c", "echo 'Backing up...'; sleep 5"]
          restartPolicy: OnFailure
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: report-generator
  namespace: data-processing
spec:
  schedule: "0 8 * * 1"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: reporter
            image: busybox:latest
            command: ["sh", "-c", "echo 'Generating report...'; sleep 15"]
          restartPolicy: OnFailure
EOF

## Kubernetes Dashboard
echo "  Deploying kubernetes dashboard..."

kubectl create deployment kubernetes-dashboard \
  --image=kubernetesui/dashboard:latest \
  --replicas=1 \
  -n kubernetes-dashboard 2>/dev/null || true

## DaemonSet example
echo "  Deploying DaemonSet (node-agent)..."

cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      containers:
      - name: agent
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo 'Monitoring node...'; sleep 60; done"]
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

echo "Workloads deployed"
echo ""

# Create additional HPAs
echo "Creating additional HPAs..."

kubectl autoscale deployment backend-api \
  --cpu-percent=80 \
  --min=1 \
  --max=5 \
  -n production 2>/dev/null || true

kubectl autoscale deployment worker \
  --cpu-percent=75 \
  --min=3 \
  --max=15 \
  -n production 2>/dev/null || true

echo "HPAs created"
echo ""

# Create more PDBs
echo "Creating additional PDBs..."

cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-api-pdb
  namespace: production
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: backend-api
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: database-pdb
  namespace: production
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: database
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: worker-pdb
  namespace: production
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: worker
EOF

echo "PDBs created"
echo ""

# Create Istio Gateway and VirtualService
echo "Creating Istio resources..."

cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: production
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend-route
  namespace: production
spec:
  hosts:
  - "*"
  gateways:
  - demo-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: frontend
        port:
          number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-route
  namespace: production
spec:
  hosts:
  - api.demo.local
  http:
  - match:
    - uri:
        prefix: "/api"
    route:
    - destination:
        host: backend-api
        port:
          number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: frontend-dr
  namespace: production
spec:
  host: frontend
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
EOF

echo "Istio resources created"
echo ""

# Wait for pods to be scheduled
echo "Waiting for pods to be scheduled (2-3 minutes)..."
sleep 90

# Check status
echo ""
echo "=========================================================================="
echo "  Cluster Status Summary"
echo "=========================================================================="
echo ""

echo "Nodes:"
kubectl get nodes
echo ""

echo "Namespaces with Istio injection:"
kubectl get namespaces -L istio-injection | grep enabled || echo "  (listing all namespaces with injection enabled)"
echo ""

echo "Pods by namespace:"
for ns in production staging development monitoring build-agents data-processing kubernetes-dashboard; do
  POD_COUNT=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "  $ns: $POD_COUNT pods"
done
echo ""

echo "Workload Summary:"
echo "  Deployments: $(kubectl get deployments -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  StatefulSets: $(kubectl get statefulsets -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  DaemonSets: $(kubectl get daemonsets -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  CronJobs: $(kubectl get cronjobs -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  HPAs: $(kubectl get hpa -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  PDBs: $(kubectl get pdb -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  PVCs: $(kubectl get pvc -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo ""

echo "Istio Resources:"
echo "  Gateways: $(kubectl get gateways -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  VirtualServices: $(kubectl get virtualservices -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo "  DestinationRules: $(kubectl get destinationrules -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
echo ""

echo "=========================================================================="
echo "  Demo Cluster Setup Complete"
echo "=========================================================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Context: $(kubectl config current-context)"
echo ""
echo "Next Steps:"
echo ""
echo "1. Wait 2-3 minutes for all pods to fully start"
echo ""
echo "2. Generate discovery report:"
echo "   bash aks-discover-v2.sh $CLUSTER_NAME html"
echo ""
echo "3. Or for specific namespace:"
echo "   bash aks-discover-v2.sh $CLUSTER_NAME html production"
echo ""
echo "4. Open the generated HTML file for screenshots"
echo ""
echo "Note: You now have a realistic demo cluster with:"
echo "  - Cluster name: $CLUSTER_NAME"
echo "  - Multiple namespaces with real workload types"
echo "  - Istio service mesh with sidecars in some namespaces"
echo "  - HPAs and PDBs configured"
echo "  - One failing pod (for demonstration)"
echo "  - StatefulSets with PVCs"
echo "  - CronJobs for scheduled tasks"
echo ""
echo "To create another cluster, run:"
echo "  ./setup-demo-cluster.sh another-cluster-name"
echo ""
echo "To switch between clusters:"
echo "  kubectl config use-context $CLUSTER_NAME"
echo "  kubectl config use-context another-cluster-name"
echo ""
echo "To list all clusters:"
echo "  minikube profile list"
echo ""