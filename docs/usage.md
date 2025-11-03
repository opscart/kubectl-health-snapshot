# Usage Guide

## Basic Usage

### Generate HTML Report
```bash
./k8s-cluster-discovery.sh my-cluster html
```

Output: `cluster-reports/my-cluster_YYYYMMDD_HHMMSS.html`

### Generate Report for Specific Namespace
```bash
./k8s-cluster-discovery.sh my-cluster html production
```

### Generate JSON for Automation
```bash
./k8s-cluster-discovery.sh my-cluster json
```

### Generate Markdown for Documentation
```bash
./k8s-cluster-discovery.sh my-cluster markdown > docs/cluster-state.md
```

## Advanced Usage

### Multiple Clusters
```bash
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

### Scheduled Health Checks
```bash
# Add to crontab
0 8 * * * cd /path/to/scripts && ./k8s-cluster-discovery.sh prod-cluster html
```

## Output Locations

./cluster-reports/
├── cluster-name_YYYYMMDD_HHMMSS.html
├── cluster-name_YYYYMMDD_HHMMSS.json
└── cluster-name_YYYYMMDD_HHMMSS.md

## Command Syntax
Usage: k8s-cluster-discovery.sh <cluster-name> <format> [namespace]
Arguments:
cluster-name    Kubernetes context name
format          html, json, or markdown
namespace       (Optional) Specific namespace
Examples:
k8s-cluster-discovery.sh prod-cluster html
k8s-cluster-discovery.sh prod-cluster json production
k8s-cluster-discovery.sh staging-cluster markdown

## Integration Examples

See [examples/](../examples/) directory for:
- Azure DevOps pipelines
- GitHub Actions workflows
- GitLab CI configurations
- Jenkins pipelines

Save each section to its respective file in your repository.