# Installation Guide

## Prerequisites

### Required Tools

#### kubectl
```bash
# macOS
brew install kubectl

# Linux (Ubuntu/Debian)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

# Windows (WSL2)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl
```

#### jq
```bash
# macOS
brew install jq

# Linux (Ubuntu/Debian)
sudo apt-get install jq

# Linux (RHEL/CentOS)
sudo yum install jq

# Windows (WSL2)
sudo apt-get install jq
```

#### bash 4.0+
```bash
# Check version
bash --version

# macOS (if needed)
brew install bash
```

### Cluster Access

Ensure kubectl is configured:
```bash
kubectl cluster-info
kubectl get nodes
```

## Installation

### Option 1: Clone Repository
```bash
git clone https://github.com/opscart/kubectl-health-snapshot.git
cd kubectl-health-snapshot
chmod +x k8s-cluster-discovery.sh
```

### Option 2: Download Script Directly
```bash
curl -O https://raw.githubusercontent.com/opscart/kubectl-health-snapshot/main/scripts/k8s-cluster-discovery.sh
chmod +x k8s-cluster-discovery.sh
```

### Option 3: Add to PATH
```bash
git clone https://github.com/opscart/kubectl-health-snapshot.git
echo 'export PATH="$PATH:$HOME/kubectl-health-snapshot/scripts"' >> ~/.bashrc
source ~/.bashrc

# Now run from anywhere
k8s-cluster-discovery.sh my-cluster html
```

## Verification
```bash
./k8s-cluster-discovery.sh --help
```

## Platform-Specific Notes

### macOS (Apple Silicon M1/M2/M3)
- Fully supported natively (no Rosetta needed)
- Use QEMU driver for minikube demo cluster
- Homebrew packages are ARM-native

### Linux
- Works on all major distributions
- Requires jq from package manager

### Windows
- Use WSL2 (Windows Subsystem for Linux)
- Install tools inside WSL2, not Windows
- Git Bash has limited support

## Troubleshooting

### kubectl not found
Ensure kubectl is in your PATH and executable.

### jq not found
Install jq using your package manager.

### Permission denied
```bash
chmod +x k8s-cluster-discovery.sh
```

### No cluster context
```bash
kubectl config use-context your-cluster
```

## Next Steps

See [Usage Guide](usage.md) for examples.