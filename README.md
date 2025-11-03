# Kubernetes Cluster Discovery Tool

Quick cluster health reports in under 60 seconds. Generate visual HTML reports, machine-readable JSON, or documentation-friendly Markdown.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.20%2B-blue.svg)](https://kubernetes.io/)

## Overview

A lightweight bash script that provides comprehensive Kubernetes cluster health snapshots in multiple formats. Works with any Kubernetes distribution - AKS, EKS, GKE, OpenShift, minikube, and more.

## Features

- **Fast Health Snapshots** - Complete cluster analysis in under 60 seconds
- **Multiple Output Formats** - HTML (visual), JSON (automation), Markdown (documentation)
- **Universal Compatibility** - Works with any Kubernetes cluster
- **Istio Service Mesh Visibility** - Gateways, VirtualServices, sidecar injection status
- **Comprehensive Workload Analysis** - Deployments, StatefulSets, CronJobs, DaemonSets
- **Smart Configuration Warnings** - Detects unusual configurations automatically
- **Zero Dependencies** - Just kubectl, jq, and bash
- **Cross-Platform** - Linux, macOS (Intel & Apple Silicon M1/M2/M3), Windows WSL2

## Quick Start

```bash
git clone https://github.com/opscart/kubectl-health-snapshot.git
cd kubectl-health-snapshot

chmod +x k8s-cluster-discovery.sh

# Generate HTML report
./k8s-cluster-discovery.sh your-cluster html

# Or JSON for automation
./k8s-cluster-discovery.sh your-cluster json

# Or Markdown for documentation
./k8s-cluster-discovery.sh your-cluster markdown
```

## Use Cases

### Daily Operations
- **Morning Health Checks** - Visual cluster overview before standup
- **Incident Response** - Fast problem identification and triage
- **Team Communication** - Share reports with non-technical stakeholders

### Automation
- **CI/CD Quality Gates** - Pre-deployment validation
- **Scheduled Reports** - Automated daily/weekly cluster snapshots
- **Custom Dashboards** - Parse JSON output for your own tools

### Documentation
- **Architecture Reviews** - Track cluster state over time in Git
- **Compliance** - Historical cluster configuration records
- **Knowledge Base** - Document current cluster topology

## Output Formats

### HTML - For Humans
Visual dashboard with color-coded health indicators, perfect for sharing with teams.

```bash
./k8s-cluster-discovery.sh prod-cluster html
```

Features:
- Color-coded summary cards (green/yellow/red)
- Interactive collapsible sections
- Complete pod tables with status
- Istio mesh visibility
- Mobile-responsive design

### JSON - For Automation
Machine-readable format for CI/CD pipelines and custom tooling.

```bash
./k8s-cluster-discovery.sh prod-cluster json
```

Use cases:
- Pre-deployment quality gates
- Custom monitoring integrations
- Data analysis and trending

### Markdown - For Documentation
Git-friendly format for tracking changes and documentation.

```bash
./k8s-cluster-discovery.sh prod-cluster markdown
```

Use cases:
- Commit to repository for version control
- Generate documentation automatically
- Compare changes over time with git diff

## Example Output

```
Cluster Report: prod-cluster
Generated: 2025-10-31 20:00:00

Summary:
  Total Pods: 248 (3 with issues)
  Deployments: 203 (198 healthy)
  Istio Sidecars: 187 (75% coverage)
  Workloads: 228 (D:203 S:3 C:5 DS:17)
```

See [screenshots](docs/screenshots/) for more examples.

## Requirements

- kubectl 1.20+
- jq (JSON processor)
- bash 4.0+

Works on:
- Linux (all major distributions)
- macOS (Intel and Apple Silicon M1/M2/M3)
- Windows (via WSL2)

## Supported Kubernetes Distributions

- **Cloud Managed**: Azure AKS, Amazon EKS, Google GKE, IBM Cloud, DigitalOcean
- **Self-Managed**: Vanilla Kubernetes, Rancher, OpenShift, VMware Tanzu
- **Local Development**: minikube, kind, k3s, Docker Desktop, MicroK8s
- **Edge/IoT**: k3s, MicroK8s, k0s

## Documentation

- [Installation Guide](docs/installation.md)
- [Usage Examples](docs/usage.md)
- [CI/CD Integration](examples/)
- [Platform Compatibility](docs/platform-compatibility.md)

## Examples

### Daily Health Check
```bash
# Generate reports for all clusters
for cluster in prod staging dev; do
  ./k8s-cluster-discovery.sh $cluster html
done
```

### CI/CD Quality Gate
```bash
./k8s-cluster-discovery.sh prod-cluster json

PROBLEMS=$(jq '[.pod_health[].problems[]] | length' cluster-reports/*.json)

if [ "$PROBLEMS" -gt 5 ]; then
  echo "Cluster unhealthy - deployment blocked"
  exit 1
fi
```

### Weekly Documentation
```bash
./k8s-cluster-discovery.sh prod-cluster markdown > docs/weekly-$(date +%Y-%m-%d).md
git add docs/
git commit -m "Weekly cluster snapshot"
```

See [examples/](examples/) for more integration patterns.

## Demo Cluster Setup

Want to try it locally? We provide a setup script:

```bash
cd scripts
./setup-demo-cluster.sh my-demo-cluster
```

This creates a realistic demo cluster with:
- Multiple namespaces
- Istio service mesh
- Various workload types
- HPAs and PDBs
- Sample applications

Works on Mac (including Apple Silicon M1/M2/M3), Linux, and Windows WSL2.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md)

Areas we'd love help with:
- Additional output formats
- More platform testing
- Integration examples
- Documentation improvements

## Related Projects

- [k8s-ai-diagnostics](https://github.com/opscart/k8s-ai-diagnostics) - AI-powered Kubernetes problem diagnosis

## Performance

Typical performance on a 250-pod cluster:
- Data collection: ~45 seconds
- Report generation: ~12 seconds
- Total: ~60 seconds

## Roadmap

- Multi-cluster comparison reports
- Historical trending analysis
- Cost analysis per namespace
- Slack/Teams webhook integration
- YAML output format

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

**opscart** - DevOps Tools & Automation

- GitHub: [@opscart](https://github.com/opscart)
- DZone: [opscart on DZone](https://dzone.com/users/opscart)

## Support

- Open an [issue](https://github.com/opscart/kubectl-health-snapshot/issues) for bugs
- Start a [discussion](https://github.com/opscart/kubectl-health-snapshot/discussions) for questions
- Star the repo if this tool helps you!

## Acknowledgments

Built to solve real Monday morning DevOps chaos. Read the story: [DZone Article](link-to-your-dzone-article)

---

If this tool saves you time, give it a star!