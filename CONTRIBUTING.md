# Contributing to Kubernetes Cluster Discovery Tool

Thank you for your interest in contributing!

## How to Contribute

### Reporting Bugs

Open an issue with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Your environment (OS, kubectl version, cluster type)

### Suggesting Features

Open an issue describing:
- The use case
- Why it would be valuable
- Possible implementation approach

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Test thoroughly on multiple platforms
5. Commit with clear messages
6. Push to your fork
7. Open a Pull Request

### Code Style

- Use 4 spaces for indentation
- Follow existing bash script style
- Add comments for complex logic
- No emojis in scripts
- Update documentation for new features

### Testing

Test on:
- Multiple Kubernetes distributions (AKS, EKS, GKE, minikube)
- Different platforms (Linux, macOS, Windows WSL2)
- Various cluster sizes

## Development Setup
```bash
git clone https://github.com/opscart/kubectl-health-snapshot.git
cd kubectl-health-snapshot

# Create demo cluster for testing
cd scripts
./setup-demo-cluster.sh test-cluster

# Test the discovery script
./k8s-cluster-discovery.sh test-cluster html
```

## Questions?

Open an issue or reach out to [@opscart](https://github.com/opscart)