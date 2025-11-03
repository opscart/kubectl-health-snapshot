#!/bin/bash

################################################################################
# AKS Cluster Discovery - Improved with Complete Pod Listing
# Shows ALL pods, not just sidecar-injected ones
# Usage: 
#   Full report:      ./k8s-cluster-discover.sh <cluster-name> [json|markdown|html]
#   Namespace report: ./k8s-dcluster-iscover.sh <cluster-name> [json|markdown|html] <namespace>
################################################################################

set -e

CLUSTER_NAME="${1:-}"
OUTPUT_FORMAT="${2:-json}"
TARGET_NAMESPACE="${3:-}"
OUTPUT_DIR="./cluster-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_DIR="./temp-$$"

if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: Cluster name is required"
    echo ""
    echo "Usage:"
    echo "  Full report:      $0 <cluster-name> [json|markdown|html]"
    echo "  Namespace report: $0 <cluster-name> [json|markdown|html] <namespace>"
    echo ""
    echo "Examples:"
    echo "  $0 my-cluster markdown"
    echo "  $0 my-cluster html kubernetes-dashboard"
    exit 1
fi

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
trap "rm -rf $TEMP_DIR" EXIT

if [ -n "$TARGET_NAMESPACE" ]; then
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Namespace-Specific Report"
    echo "║  Cluster: $CLUSTER_NAME"
    echo "║  Namespace: $TARGET_NAMESPACE"
    echo "║  Output: $OUTPUT_FORMAT"
    echo "╚════════════════════════════════════════════════════════════╝"
else
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Full Cluster Report"
    echo "║  Cluster: $CLUSTER_NAME"
    echo "║  Output: $OUTPUT_FORMAT"
    echo "╚════════════════════════════════════════════════════════════╝"
fi
echo ""

# Get cluster info
echo "Collecting cluster information..."
# Try new format first (kubectl 1.28+), fallback to old format
CLUSTER_VERSION=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null)
if [ -z "$CLUSTER_VERSION" ] || [ "$CLUSTER_VERSION" = "null" ]; then
    CLUSTER_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')
fi
if [ -z "$CLUSTER_VERSION" ]; then
    CLUSTER_VERSION="N/A"
fi
echo "  ✓ Version: $CLUSTER_VERSION"

# Check if namespace exists (if specified)
if [ -n "$TARGET_NAMESPACE" ]; then
    if ! kubectl get namespace "$TARGET_NAMESPACE" >/dev/null 2>&1; then
        echo "❌ Error: Namespace '$TARGET_NAMESPACE' does not exist"
        exit 1
    fi
    echo "  ✓ Namespace '$TARGET_NAMESPACE' found"
fi

# Get nodes (always needed for context)
echo "Collecting node information..."
kubectl get nodes -o json 2>/dev/null > "$TEMP_DIR/nodes_raw.json" || echo '{"items":[]}' > "$TEMP_DIR/nodes_raw.json"

cat "$TEMP_DIR/nodes_raw.json" | jq '
  if .items == null then []
  else
    [.items[] |
     select(type == "object") |
     select(has("metadata")) |
     {
       name: (.metadata.name // "unknown"),
       pool: (.metadata.labels.agentpool // .metadata.labels["kubernetes.azure.com/agentpool"] // "unknown"),
       mode: (.metadata.labels["kubernetes.azure.com/mode"] // "unknown"),
       ready: ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0),
       spot: ((.metadata.labels["kubernetes.azure.com/scalesetpriority"] // "regular") == "Spot"),
       taints: [.spec.taints[]? | {key, value, effect}],
       labels: (.metadata.labels // {})
     }]
  end
' > "$TEMP_DIR/nodes_processed.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/nodes_processed.json"

cat "$TEMP_DIR/nodes_processed.json" | jq 'group_by(.pool) | map({
  pool: (.[0].pool // "unknown"),
  mode: (.[0].mode // "unknown"),
  count: length,
  ready: ([.[] | select(.ready == true)] | length),
  spot: (.[0].spot // false),
  taints: ([.[].taints[]] | unique),
  common_labels: (.[0].labels // {})
})' > "$TEMP_DIR/pools.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/pools.json"

NODE_COUNT=$(jq '[.[].count] | add // 0' "$TEMP_DIR/pools.json")
READY_COUNT=$(jq '[.[].ready] | add // 0' "$TEMP_DIR/pools.json")
echo "  ✓ Nodes: $READY_COUNT/$NODE_COUNT ready"

# Namespace-specific or full collection
if [ -n "$TARGET_NAMESPACE" ]; then
    NS_FLAG="-n $TARGET_NAMESPACE"
    NS_FILTER="--namespace=$TARGET_NAMESPACE"
else
    NS_FLAG="-A"
    NS_FILTER=""
fi

# Get namespace details
echo "Collecting namespace information..."
if [ -n "$TARGET_NAMESPACE" ]; then
    kubectl get namespace "$TARGET_NAMESPACE" -o json 2>/dev/null | jq '[. |
      select(type == "object") |
      {
        name: (.metadata.name // "unknown"),
        labels: (.metadata.labels // {}),
        annotations: (.metadata.annotations // {}),
        istio_injection: ((.metadata.labels["istio-injection"] // "disabled") == "enabled"),
        istio_rev: (.metadata.labels["istio.io/rev"] // null),
        node_selector: (.metadata.annotations["scheduler.alpha.kubernetes.io/node-selector"] // null),
        default_tolerations: (.metadata.annotations["scheduler.alpha.kubernetes.io/defaultTolerations"] // null)
      }]' > "$TEMP_DIR/namespaces.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/namespaces.json"
else
    kubectl get namespaces -o json 2>/dev/null | jq '[.items[] |
      select(type == "object") |
      {
        name: (.metadata.name // "unknown"),
        labels: (.metadata.labels // {}),
        annotations: (.metadata.annotations // {}),
        istio_injection: ((.metadata.labels["istio-injection"] // "disabled") == "enabled"),
        istio_rev: (.metadata.labels["istio.io/rev"] // null),
        node_selector: (.metadata.annotations["scheduler.alpha.kubernetes.io/node-selector"] // null),
        default_tolerations: (.metadata.annotations["scheduler.alpha.kubernetes.io/defaultTolerations"] // null)
      }]' > "$TEMP_DIR/namespaces.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/namespaces.json"
fi

NS_COUNT=$(jq 'length' "$TEMP_DIR/namespaces.json")
ISTIO_INJECTED=$(jq '[.[] | select(.istio_injection == true)] | length' "$TEMP_DIR/namespaces.json")

if [ -n "$TARGET_NAMESPACE" ]; then
    ISTIO_STATUS=$(jq -r '.[0].istio_injection' "$TEMP_DIR/namespaces.json")
    echo "  ✓ Namespace: $TARGET_NAMESPACE (Istio injection: $ISTIO_STATUS)"
else
    echo "  ✓ Namespaces: $NS_COUNT ($ISTIO_INJECTED with Istio injection)"
fi

# Istio analysis
echo "🌐 Checking Istio..."
ISTIO_NS=$(kubectl get ns -o json 2>/dev/null | jq -r '
  [.items[]? | select(.metadata.name | contains("istio")) | .metadata.name] | .[0] // ""
')

if [ -n "$ISTIO_NS" ]; then
  ISTIO_VERSION=$(kubectl get deploy -n "$ISTIO_NS" istiod -o json 2>/dev/null | jq -r '.spec.template.spec.containers[0].image // "unknown"' | cut -d: -f2 || echo "unknown")
  
  if [ -n "$TARGET_NAMESPACE" ]; then
    # Namespace-specific Istio resources
    kubectl get gateway -n "$TARGET_NAMESPACE" -o json 2>/dev/null | jq '[.items[]? | {
      name: .metadata.name, namespace: .metadata.namespace, servers: .spec.servers
    }]' > "$TEMP_DIR/istio_gateways.json" || echo '[]' > "$TEMP_DIR/istio_gateways.json"
    
    kubectl get virtualservice -n "$TARGET_NAMESPACE" -o json 2>/dev/null | jq '[.items[]? | {
      name: .metadata.name, namespace: .metadata.namespace, hosts: .spec.hosts, gateways: .spec.gateways
    }]' > "$TEMP_DIR/istio_vs.json" || echo '[]' > "$TEMP_DIR/istio_vs.json"
    
    kubectl get destinationrule -n "$TARGET_NAMESPACE" -o json 2>/dev/null | jq '[.items[]? | {
      name: .metadata.name, namespace: .metadata.namespace, host: .spec.host
    }]' > "$TEMP_DIR/istio_dr.json" || echo '[]' > "$TEMP_DIR/istio_dr.json"
  else
    # Full cluster Istio resources
    kubectl get gateway -A -o json 2>/dev/null | jq '[.items[]? | {
      name: .metadata.name, namespace: .metadata.namespace, servers: .spec.servers
    }]' > "$TEMP_DIR/istio_gateways.json" || echo '[]' > "$TEMP_DIR/istio_gateways.json"
    
    kubectl get virtualservice -A -o json 2>/dev/null | jq '[.items[]? | {
      name: .metadata.name, namespace: .metadata.namespace, hosts: .spec.hosts, gateways: .spec.gateways
    }]' > "$TEMP_DIR/istio_vs.json" || echo '[]' > "$TEMP_DIR/istio_vs.json"
    
    kubectl get destinationrule -A -o json 2>/dev/null | jq '[.items[]? | {
      name: .metadata.name, namespace: .metadata.namespace, host: .spec.host
    }]' > "$TEMP_DIR/istio_dr.json" || echo '[]' > "$TEMP_DIR/istio_dr.json"
  fi
  
  GATEWAY_COUNT=$(jq 'length' "$TEMP_DIR/istio_gateways.json")
  VS_COUNT=$(jq 'length' "$TEMP_DIR/istio_vs.json")
  
  cat > "$TEMP_DIR/istio.json" <<EOF
{
  "installed": true,
  "version": "$ISTIO_VERSION",
  "namespace": "$ISTIO_NS",
  "gateways": $(cat "$TEMP_DIR/istio_gateways.json"),
  "virtual_services": $(cat "$TEMP_DIR/istio_vs.json"),
  "destination_rules": $(cat "$TEMP_DIR/istio_dr.json"),
  "stats": {
    "gateway_count": $GATEWAY_COUNT,
    "virtual_service_count": $VS_COUNT
  }
}
EOF
  
  echo "  ✓ Istio: $ISTIO_VERSION (Gateways: $GATEWAY_COUNT, VS: $VS_COUNT)"
else
  echo '{"installed": false}' > "$TEMP_DIR/istio.json"
  echo "  ⓘ Istio not installed"
fi

# Workloads
echo "Collecting workloads..."
kubectl get statefulsets $NS_FLAG -o json 2>/dev/null | jq '[.items[]? |
  select(type == "object") | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    replicas: .spec.replicas,
    ready_replicas: (.status.readyReplicas // 0),
    labels: .metadata.labels,
    update_strategy: .spec.updateStrategy.type,
    volume_claim_templates: [.spec.volumeClaimTemplates[]? | {
      name: .metadata.name, storage_class: .spec.storageClassName, size: .spec.resources.requests.storage
    }],
    tolerations: [.spec.template.spec.tolerations[]? | {key, operator, value, effect}],
    node_selector: .spec.template.spec.nodeSelector,
    healthy: ((.status.readyReplicas // 0) == .spec.replicas)
  }]' > "$TEMP_DIR/statefulsets.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/statefulsets.json"

kubectl get cronjobs $NS_FLAG -o json 2>/dev/null | jq '[.items[]? |
  select(type == "object") | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    schedule: .spec.schedule,
    suspend: (.spec.suspend // false),
    active: (.status.active // [] | length),
    last_schedule: .status.lastScheduleTime,
    last_successful: .status.lastSuccessfulTime,
    labels: .metadata.labels,
    tolerations: [.spec.jobTemplate.spec.template.spec.tolerations[]? | {key, operator, value, effect}],
    node_selector: .spec.jobTemplate.spec.template.spec.nodeSelector
  }]' > "$TEMP_DIR/cronjobs.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/cronjobs.json"

kubectl get daemonsets $NS_FLAG -o json 2>/dev/null | jq '[.items[]? |
  select(type == "object") | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    desired: .status.desiredNumberScheduled,
    ready: (.status.numberReady // 0),
    available: (.status.numberAvailable // 0),
    unavailable: (.status.numberUnavailable // 0),
    labels: .metadata.labels,
    tolerations: [.spec.template.spec.tolerations[]? | {key, operator, value, effect}],
    node_selector: .spec.template.spec.nodeSelector,
    healthy: ((.status.numberReady // 0) == .status.desiredNumberScheduled)
  }]' > "$TEMP_DIR/daemonsets.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/daemonsets.json"

kubectl get deployments $NS_FLAG -o json 2>/dev/null | jq '[.items[]? |
  select(type == "object") | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    replicas: .spec.replicas,
    ready_replicas: (.status.readyReplicas // 0),
    available_replicas: (.status.availableReplicas // 0),
    labels: .metadata.labels,
    tolerations: [.spec.template.spec.tolerations[]? | {key, operator, value, effect}],
    node_selector: .spec.template.spec.nodeSelector,
    healthy: ((.status.readyReplicas // 0) == .spec.replicas)
  }]' > "$TEMP_DIR/deployments.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/deployments.json"

STS_COUNT=$(jq 'length' "$TEMP_DIR/statefulsets.json")
CRON_COUNT=$(jq 'length' "$TEMP_DIR/cronjobs.json")
DS_COUNT=$(jq 'length' "$TEMP_DIR/daemonsets.json")
DEPLOY_COUNT=$(jq 'length' "$TEMP_DIR/deployments.json")
echo "  ✓ Deployments: $DEPLOY_COUNT | StatefulSets: $STS_COUNT | CronJobs: $CRON_COUNT | DaemonSets: $DS_COUNT"

# Pods - COMPLETE LIST with sidecar info
echo "Analyzing ALL pods..."
kubectl get pods $NS_FLAG -o json 2>/dev/null | jq '[.items[]? |
  select(type == "object") | {
    ns: .metadata.namespace,
    name: .metadata.name,
    phase: .status.phase,
    ready: ([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0),
    containers: (
      if .spec.containers != null then
        [.spec.containers[] | .name]
      else
        []
      end
    ),
    container_count: (
      if .spec.containers != null then
        .spec.containers | length
      else
        0
      end
    ),
    ready_containers: (
      if .status.containerStatuses != null then
        [.status.containerStatuses[] | select(.ready == true)] | length
      else
        0
      end
    ),
    has_sidecar: (
      (.metadata.annotations["sidecar.istio.io/status"] != null) or
      ([.spec.containers[]? | select(.name == "istio-proxy")] | length > 0)
    ),
    sidecar_version: (
      if ([.spec.containers[]? | select(.name == "istio-proxy")] | length > 0) then
        ([.spec.containers[] | select(.name == "istio-proxy") | .image] | .[0] | split(":")[1] // "unknown")
      else
        null
      end
    ),
    problem: (.status.phase != "Running" and .status.phase != "Succeeded"),
    reason: ([.status.containerStatuses[]? | .state.waiting.reason] | map(select(. != null)) | .[0] // .status.phase),
    restart_count: ([.status.containerStatuses[]? | .restartCount] | add // 0),
    node_name: .spec.nodeName,
    tolerations: [.spec.tolerations[]? | {key, operator, value, effect}]
  }]' > "$TEMP_DIR/all_pods.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/all_pods.json"

# Group pods by namespace
cat "$TEMP_DIR/all_pods.json" | jq 'group_by(.ns) | map({
  namespace: .[0].ns,
  total: length,
  running: ([.[] | select(.phase == "Running")] | length),
  with_sidecar: ([.[] | select(.has_sidecar == true)] | length),
  pods: .,
  problems: [.[] | select(.problem == true) | {name, reason, restart_count}]
})' > "$TEMP_DIR/pod_health.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/pod_health.json"

TOTAL_PODS=$(jq '[.[].total] | add // 0' "$TEMP_DIR/pod_health.json")
PROBLEM_PODS=$(jq '[.[].problems[]] | length' "$TEMP_DIR/pod_health.json")
SIDECAR_PODS=$(jq '[.[].with_sidecar] | add // 0' "$TEMP_DIR/pod_health.json")
echo "  ✓ Pods: $TOTAL_PODS total ($SIDECAR_PODS with sidecars, $PROBLEM_PODS with issues)"

# HPAs & PDBs
echo "⚖️  Collecting HPAs & PDBs..."
kubectl get hpa $NS_FLAG -o json 2>/dev/null | jq '[.items[]? | {
  ns: .metadata.namespace, name: .metadata.name, min: .spec.minReplicas, max: .spec.maxReplicas
}]' > "$TEMP_DIR/hpa.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/hpa.json"

kubectl get pdb $NS_FLAG -o json 2>/dev/null | jq '[.items[]? | {
  ns: .metadata.namespace, name: .metadata.name, min: .spec.minAvailable, disruptions: (.status.disruptionsAllowed // 0)
}]' > "$TEMP_DIR/pdb.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/pdb.json"

HPA_COUNT=$(jq 'length' "$TEMP_DIR/hpa.json")
PDB_COUNT=$(jq 'length' "$TEMP_DIR/pdb.json")
echo "  ✓ HPAs: $HPA_COUNT | PDBs: $PDB_COUNT"

# Storage
echo "Collecting storage..."
kubectl get pvc $NS_FLAG -o json 2>/dev/null | jq '[.items[]? | {
  ns: .metadata.namespace, name: .metadata.name, status: .status.phase,
  size: .spec.resources.requests.storage, storage_class: .spec.storageClassName
}]' > "$TEMP_DIR/pvc.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/pvc.json"

PVC_COUNT=$(jq 'length' "$TEMP_DIR/pvc.json")
echo "  ✓ PVCs: $PVC_COUNT"

echo ""
echo "Generating report..."

# Generate markdown output
if [ "$OUTPUT_FORMAT" == "markdown" ]; then
  if [ -n "$TARGET_NAMESPACE" ]; then
    OUTPUT_FILE="$OUTPUT_DIR/${CLUSTER_NAME}_${TARGET_NAMESPACE}_${TIMESTAMP}.md"
  else
    OUTPUT_FILE="$OUTPUT_DIR/${CLUSTER_NAME}_${TIMESTAMP}.md"
  fi
  
  cat > "$OUTPUT_FILE" <<EOF
# AKS Cluster Report: $CLUSTER_NAME
$(if [ -n "$TARGET_NAMESPACE" ]; then echo "## Namespace: $TARGET_NAMESPACE"; fi)

**Generated:** $(date)  
**Kubernetes Version:** $CLUSTER_VERSION

EOF

  if [ -z "$TARGET_NAMESPACE" ]; then
    cat >> "$OUTPUT_FILE" <<EOF
---

## Node Pools Summary

EOF
    jq -r '.[] | "### \(.pool) (\(.mode) mode)\n- **Count:** \(.count) nodes | **Ready:** \(.ready)/\(.count)\n\(if .spot then "- **Type:** ⚡ Spot Instances\n" else "" end)\(if (.taints | length > 0) then "- **Taints:** " + ([.taints[] | "`\(.key):\(.effect)`"] | join(", ")) + "\n" else "" end)\n"' "$TEMP_DIR/pools.json" >> "$OUTPUT_FILE"
  fi

  cat >> "$OUTPUT_FILE" <<EOF
---

## Namespace Configuration

EOF

  jq -r '.[] | "### \(.name)\n\n**Istio Injection:** \(if .istio_injection then "Enabled" else "❌ Disabled" end)\(if .istio_rev != null then " (revision: `\(.istio_rev)`)" else "" end)\n\n**Labels:**\n```yaml\n\(.labels | to_entries | map("\(.key): \(.value)") | join("\n"))\n```\n\n\(if .node_selector != null then "⚠️ **Node Selector Annotation:** `\(.node_selector)`\n\n" else "" end)\(if .default_tolerations != null then "**Default Tolerations:** \n```json\n\(.default_tolerations)\n```\n\n" else "" end)"' "$TEMP_DIR/namespaces.json" >> "$OUTPUT_FILE"

  if [ "$(jq -r '.installed' "$TEMP_DIR/istio.json")" == "true" ]; then
    cat >> "$OUTPUT_FILE" <<EOF
---

## 🌐 Istio Service Mesh

**Version:** $(jq -r '.version' "$TEMP_DIR/istio.json") | **Control Plane Namespace:** $(jq -r '.namespace' "$TEMP_DIR/istio.json")

### Gateways ($(jq -r '.stats.gateway_count' "$TEMP_DIR/istio.json"))

EOF
    if [ "$(jq -r '.stats.gateway_count' "$TEMP_DIR/istio.json")" -gt 0 ]; then
      jq -r '.gateways[] | "- **\(.namespace)/\(.name)**"' "$TEMP_DIR/istio.json" >> "$OUTPUT_FILE"
    else
      echo "*No gateways configured in this namespace*" >> "$OUTPUT_FILE"
    fi

    cat >> "$OUTPUT_FILE" <<EOF

### VirtualServices ($(jq -r '.stats.virtual_service_count' "$TEMP_DIR/istio.json"))

EOF
    if [ "$(jq -r '.stats.virtual_service_count' "$TEMP_DIR/istio.json")" -gt 0 ]; then
      jq -r '.virtual_services[] | "- **\(.namespace)/\(.name)**: \(.hosts | join(", "))"' "$TEMP_DIR/istio.json" >> "$OUTPUT_FILE"
    else
      echo "*No virtual services configured in this namespace*" >> "$OUTPUT_FILE"
    fi
  fi

  cat >> "$OUTPUT_FILE" <<EOF

---

## Workloads

### Deployments ($DEPLOY_COUNT)

EOF
  if [ "$DEPLOY_COUNT" -gt 0 ]; then
    jq -r '.[] | "#### \(.namespace)/\(.name)\n- **Replicas:** \(.ready_replicas)/\(.replicas) ready | **Available:** \(.available_replicas) | **Status:** \(if .healthy then "✅" else "❌" end)\n\(if .tolerations | length > 0 then "- **Tolerations:** " + ([.tolerations[] | "`\(.key // "*"):\(.effect)`"] | join(", ")) + "\n" else "" end)\(if .node_selector != null and (.node_selector | length > 0) then "- **Node Selector:** `" + (.node_selector | to_entries | map("\(.key)=\(.value)") | join(", ")) + "`\n" else "" end)\n"' "$TEMP_DIR/deployments.json" >> "$OUTPUT_FILE"
  else
    echo "*No deployments*" >> "$OUTPUT_FILE"
  fi

  cat >> "$OUTPUT_FILE" <<EOF

### StatefulSets ($STS_COUNT)

EOF
  if [ "$STS_COUNT" -gt 0 ]; then
    jq -r '.[] | "#### \(.namespace)/\(.name)\n- **Replicas:** \(.ready_replicas)/\(.replicas) | **Strategy:** \(.update_strategy) | **Status:** \(if .healthy then "✅" else "❌" end)\n- **Volumes:** \(.volume_claim_templates | map("\(.name) (\(.size))") | join(", "))\n\(if .tolerations | length > 0 then "- **Tolerations:** " + ([.tolerations[] | "`\(.key // "*"):\(.effect)`"] | join(", ")) + "\n" else "" end)\n"' "$TEMP_DIR/statefulsets.json" >> "$OUTPUT_FILE"
  else
    echo "*No StatefulSets*" >> "$OUTPUT_FILE"
  fi

  cat >> "$OUTPUT_FILE" <<EOF

### CronJobs ($CRON_COUNT)

EOF
  if [ "$CRON_COUNT" -gt 0 ]; then
    jq -r '.[] | "#### \(.namespace)/\(.name)\n- **Schedule:** `\(.schedule)` | **Suspended:** \(if .suspend then "✅" else "❌" end) | **Active:** \(.active)\n- **Last Run:** \(.last_schedule // "Never")\n\(if .tolerations | length > 0 then "- **Tolerations:** " + ([.tolerations[] | "`\(.key // "*"):\(.effect)`"] | join(", ")) + "\n" else "" end)\n"' "$TEMP_DIR/cronjobs.json" >> "$OUTPUT_FILE"
  else
    echo "*No CronJobs*" >> "$OUTPUT_FILE"
  fi

  cat >> "$OUTPUT_FILE" <<EOF

### DaemonSets ($DS_COUNT)

EOF
  if [ "$DS_COUNT" -gt 0 ]; then
    jq -r '.[] | "#### \(.namespace)/\(.name)\n- **Ready:** \(.ready)/\(.desired) | **Status:** \(if .healthy then "✅" else "❌" end)\n\(if .unavailable > 0 then "- ⚠️ **Unavailable:** \(.unavailable)\n" else "" end)\(if .tolerations | length > 0 then "- **Tolerations:** " + ([.tolerations[] | "`\(.key // "*"):\(.effect)`"] | join(", ")) + "\n" else "" end)\n"' "$TEMP_DIR/daemonsets.json" >> "$OUTPUT_FILE"
  else
    echo "*No DaemonSets*" >> "$OUTPUT_FILE"
  fi

  cat >> "$OUTPUT_FILE" <<EOF

---

## All Pods

EOF

  jq -r '.[] | "### \(.namespace)\n\n**Summary:** \(.total) pods | \(.running) running | \(.with_sidecar) with Istio sidecar\n\n#### Pod List\n\n| Pod Name | Status | Ready | Containers | Sidecar | Restarts | Node |\n|----------|--------|-------|------------|---------|----------|------|\n" + (.pods[] | "| `\(.name)` | \(.phase) | \(if .ready then "✅" else "❌" end) | \(.ready_containers)/\(.container_count) | \(if .has_sidecar then "✅" else "❌" end) | \(.restart_count) | \(.node_name // "N/A") |") + "\n\n\(if .problems | length > 0 then "#### ⚠️ Problem Pods\n\n" + (.problems | map("- ❌ **\(.name)**: \(.reason) (restarts: \(.restart_count))") | join("\n")) + "\n\n" else "" end)"' "$TEMP_DIR/pod_health.json" >> "$OUTPUT_FILE"

  cat >> "$OUTPUT_FILE" <<EOF

---

## Autoscaling & Storage

**HPAs:** $HPA_COUNT | **PDBs:** $PDB_COUNT | **PVCs:** $PVC_COUNT

EOF
  if [ "$HPA_COUNT" -gt 0 ]; then
    echo "### HPAs" >> "$OUTPUT_FILE"
    jq -r '.[] | "- **\(.ns)/\(.name)**: min=\(.min), max=\(.max)"' "$TEMP_DIR/hpa.json" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
  fi

  if [ "$PDB_COUNT" -gt 0 ]; then
    echo "### PDBs" >> "$OUTPUT_FILE"
    jq -r '.[] | "- **\(.ns)/\(.name)**: min=\(.min // "N/A"), disruptions=\(.disruptions)"' "$TEMP_DIR/pdb.json" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
  fi

  if [ "$PVC_COUNT" -gt 0 ]; then
    echo "### PVCs" >> "$OUTPUT_FILE"
    jq -r 'group_by(.ns) | map("#### \(.[0].ns)\n" + (. | map("- **\(.name)**: \(.size) (\(.storage_class)) - \(.status)") | join("\n"))) | join("\n\n")' "$TEMP_DIR/pvc.json" >> "$OUTPUT_FILE"
  fi

  echo ""
  echo "Markdown report: $OUTPUT_FILE"
  
elif [ "$OUTPUT_FORMAT" == "html" ]; then
  # HTML output
  if [ -n "$TARGET_NAMESPACE" ]; then
    OUTPUT_FILE="$OUTPUT_DIR/${CLUSTER_NAME}_${TARGET_NAMESPACE}_${TIMESTAMP}.html"
  else
    OUTPUT_FILE="$OUTPUT_DIR/${CLUSTER_NAME}_${TIMESTAMP}.html"
  fi
  
  # Calculate summary stats
  TOTAL_DEPLOYMENTS=$(jq 'length' "$TEMP_DIR/deployments.json")
  HEALTHY_DEPLOYMENTS=$(jq '[.[] | select(.healthy == true)] | length' "$TEMP_DIR/deployments.json")
  ISTIO_INSTALLED=$(jq -r '.installed' "$TEMP_DIR/istio.json")
  
  # Warnings check
  HAS_WARNINGS=false
  NODE_SELECTOR_WARNING=""
  if [ -n "$TARGET_NAMESPACE" ]; then
    NODE_SELECTOR=$(jq -r '.[0].node_selector // ""' "$TEMP_DIR/namespaces.json")
    if [[ "$NODE_SELECTOR" == *"mode=system"* ]]; then
      HAS_WARNINGS=true
      NODE_SELECTOR_WARNING="Namespace has node selector annotation set to <code>$NODE_SELECTOR</code>. This schedules pods on system node pools, which is unusual for user applications."
    fi
  fi
  
  cat > "$OUTPUT_FILE" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AKS Cluster Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; background: #f5f7fa; color: #2c3e50; line-height: 1.6; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px; border-radius: 12px; margin-bottom: 30px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .header h1 { font-size: 32px; margin-bottom: 15px; font-weight: 600; }
        .header-meta { opacity: 0.95; font-size: 14px; }
        .header-meta div { margin: 5px 0; }
        
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); transition: transform 0.2s; }
        .summary-card:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.12); }
        .summary-card.success { border-left: 4px solid #10b981; }
        .summary-card.warning { border-left: 4px solid #f59e0b; }
        .summary-card.error { border-left: 4px solid #ef4444; }
        .summary-card.info { border-left: 4px solid #3b82f6; }
        .card-label { font-size: 13px; color: #6b7280; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px; font-weight: 500; }
        .card-value { font-size: 36px; font-weight: 700; color: #1f2937; line-height: 1; }
        .card-subtitle { font-size: 13px; color: #6b7280; margin-top: 8px; }
        
        .alert { padding: 16px 20px; border-radius: 8px; margin-bottom: 25px; border-left: 4px solid; }
        .alert.warning { background: #fffbeb; border-color: #f59e0b; color: #92400e; }
        .alert.info { background: #eff6ff; border-color: #3b82f6; color: #1e40af; }
        .alert strong { font-weight: 600; }
        
        .section { background: white; border-radius: 12px; padding: 25px; margin-bottom: 25px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
        .section-header { display: flex; justify-content: space-between; align-items: center; cursor: pointer; user-select: none; padding-bottom: 15px; border-bottom: 2px solid #e5e7eb; }
        .section-header h2 { font-size: 20px; font-weight: 600; color: #1f2937; }
        .section-header .toggle { color: #6b7280; font-size: 18px; transition: transform 0.3s; }
        .section-content { margin-top: 20px; }
        .section-content.collapsed { display: none; }
        
        table { width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 15px; }
        thead { background: #f9fafb; }
        th { padding: 12px 16px; text-align: left; font-weight: 600; color: #374151; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px; border-bottom: 2px solid #e5e7eb; }
        td { padding: 12px 16px; border-bottom: 1px solid #f3f4f6; font-size: 14px; }
        tbody tr:hover { background: #f9fafb; }
        tbody tr:last-child td { border-bottom: none; }
        
        .badge { display: inline-block; padding: 4px 10px; border-radius: 12px; font-size: 12px; font-weight: 500; }
        .badge.success { background: #d1fae5; color: #065f46; }
        .badge.warning { background: #fed7aa; color: #92400e; }
        .badge.error { background: #fee2e2; color: #991b1b; }
        .badge.info { background: #dbeafe; color: #1e40af; }
        
        .status-dot { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 6px; }
        .status-dot.green { background: #10b981; }
        .status-dot.red { background: #ef4444; }
        .status-dot.yellow { background: #f59e0b; }
        
        code { background: #f3f4f6; padding: 2px 6px; border-radius: 4px; font-family: 'Courier New', monospace; font-size: 13px; color: #1f2937; }
        
        .empty-state { text-align: center; padding: 40px; color: #9ca3af; }
        .empty-state-icon { font-size: 48px; margin-bottom: 10px; }
        
        .footer { text-align: center; padding: 30px 0; color: #6b7280; font-size: 13px; border-top: 1px solid #e5e7eb; margin-top: 40px; }
        
        @media print {
            body { background: white; }
            .header { background: #667eea; }
            .no-print { display: none; }
            .section { page-break-inside: avoid; }
        }
        
        @media (max-width: 768px) {
            .summary-grid { grid-template-columns: 1fr; }
            .header h1 { font-size: 24px; }
            .card-value { font-size: 28px; }
        }
    </style>
</head>
<body>
    <div class="container">
HTMLEOF

  # Add dynamic header
  cat >> "$OUTPUT_FILE" << EOF
        <div class="header">
            <h1>AKS Cluster Report</h1>
            <div class="header-meta">
                <div><strong>Cluster:</strong> $CLUSTER_NAME</div>
$(if [ -n "$TARGET_NAMESPACE" ]; then echo "                <div><strong>Namespace:</strong> $TARGET_NAMESPACE</div>"; fi)
                <div><strong>Generated:</strong> $(date)</div>
                <div><strong>Kubernetes Version:</strong> $CLUSTER_VERSION</div>
            </div>
        </div>

        <div class="summary-grid">
            <div class="summary-card $([ "$PROBLEM_PODS" -eq 0 ] && echo "success" || echo "error")">
                <div class="card-label">Total Pods</div>
                <div class="card-value">$TOTAL_PODS</div>
                <div class="card-subtitle">$([ "$PROBLEM_PODS" -gt 0 ] && echo "$PROBLEM_PODS with issues" || echo "All healthy")</div>
            </div>
            <div class="summary-card $([ "$DEPLOY_COUNT" -eq "$HEALTHY_DEPLOYMENTS" ] && echo "success" || echo "warning")">
                <div class="card-label">Deployments</div>
                <div class="card-value">$DEPLOY_COUNT</div>
                <div class="card-subtitle">$HEALTHY_DEPLOYMENTS healthy</div>
            </div>
            <div class="summary-card info">
                <div class="card-label">Istio Sidecars</div>
                <div class="card-value">$SIDECAR_PODS</div>
                <div class="card-subtitle">$([ "$TOTAL_PODS" -gt 0 ] && echo "$((SIDECAR_PODS * 100 / TOTAL_PODS))% coverage" || echo "0% coverage")</div>
            </div>
            <div class="summary-card info">
                <div class="card-label">Workloads</div>
                <div class="card-value">$((DEPLOY_COUNT + STS_COUNT + CRON_COUNT + DS_COUNT))</div>
                <div class="card-subtitle">D:$DEPLOY_COUNT S:$STS_COUNT C:$CRON_COUNT DS:$DS_COUNT</div>
            </div>
        </div>

$(if [ "$HAS_WARNINGS" = true ]; then echo "        <div class=\"alert warning\">
            <strong>⚠️ Configuration Warning:</strong> $NODE_SELECTOR_WARNING
        </div>"; fi)
EOF

  # Namespace section
  cat >> "$OUTPUT_FILE" << 'EOF'
        <div class="section">
            <div class="section-header" onclick="toggleSection('namespace')">
                <h2>📦 Namespace Configuration</h2>
                <span class="toggle">▼</span>
            </div>
            <div id="namespace" class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>Property</th>
                            <th>Value</th>
                        </tr>
                    </thead>
                    <tbody>
EOF

  # Add namespace details dynamically
  jq -r '.[] | [
    "<tr><td>Name</td><td><code>\(.name)</code></td></tr>",
    "<tr><td>Istio Injection</td><td>\(if .istio_injection then "<span class=\"badge success\">Enabled</span>" else "<span class=\"badge error\">❌ Disabled</span>" end)\(if .istio_rev != null then " (revision: <code>\(.istio_rev)</code>)" else "" end)</td></tr>",
    (if .node_selector != null then "<tr><td>Node Selector ⚠️</td><td><code>\(.node_selector)</code></td></tr>" else "" end),
    "<tr><td>Labels</td><td>\(.labels | to_entries | map("<code>\(.key): \(.value)</code>") | join("<br>"))</td></tr>"
  ] | join("")' "$TEMP_DIR/namespaces.json" >> "$OUTPUT_FILE"

  cat >> "$OUTPUT_FILE" << 'EOF'
                    </tbody>
                </table>
            </div>
        </div>
EOF

  # Istio section
  if [ "$ISTIO_INSTALLED" == "true" ]; then
    ISTIO_VERSION=$(jq -r '.version' "$TEMP_DIR/istio.json")
    ISTIO_NS=$(jq -r '.namespace' "$TEMP_DIR/istio.json")
    GW_COUNT=$(jq -r '.stats.gateway_count' "$TEMP_DIR/istio.json")
    VS_COUNT=$(jq -r '.stats.virtual_service_count' "$TEMP_DIR/istio.json")
    
    cat >> "$OUTPUT_FILE" << EOF
        <div class="section">
            <div class="section-header" onclick="toggleSection('istio')">
                <h2>🌐 Istio Service Mesh</h2>
                <span class="toggle">▼</span>
            </div>
            <div id="istio" class="section-content">
                <p><strong>Version:</strong> $ISTIO_VERSION | <strong>Control Plane:</strong> $ISTIO_NS</p>
                
                <h3 style="margin-top: 20px; margin-bottom: 10px; font-size: 16px;">Gateways ($GW_COUNT)</h3>
EOF
    
    if [ "$GW_COUNT" -gt 0 ]; then
      echo "                <ul style='margin-left: 20px;'>" >> "$OUTPUT_FILE"
      jq -r '.gateways[] | "<li><code>\(.namespace)/\(.name)</code></li>"' "$TEMP_DIR/istio.json" >> "$OUTPUT_FILE"
      echo "                </ul>" >> "$OUTPUT_FILE"
    else
      echo "                <div class=\"alert info\" style=\"margin-top: 10px;\">No gateways configured in this namespace</div>" >> "$OUTPUT_FILE"
    fi
    
    cat >> "$OUTPUT_FILE" << EOF
                
                <h3 style="margin-top: 20px; margin-bottom: 10px; font-size: 16px;">VirtualServices ($VS_COUNT)</h3>
EOF
    
    if [ "$VS_COUNT" -gt 0 ]; then
      echo "                <ul style='margin-left: 20px;'>" >> "$OUTPUT_FILE"
      jq -r '.virtual_services[] | "<li><code>\(.namespace)/\(.name)</code>: \(.hosts | join(", "))</li>"' "$TEMP_DIR/istio.json" >> "$OUTPUT_FILE"
      echo "                </ul>" >> "$OUTPUT_FILE"
    else
      echo "                <div class=\"alert info\" style=\"margin-top: 10px;\">No virtual services configured in this namespace</div>" >> "$OUTPUT_FILE"
    fi
    
    echo "            </div>" >> "$OUTPUT_FILE"
    echo "        </div>" >> "$OUTPUT_FILE"
  fi

  # Workloads section
  cat >> "$OUTPUT_FILE" << EOF
        <div class="section">
            <div class="section-header" onclick="toggleSection('workloads')">
                <h2>🗄️ Workloads</h2>
                <span class="toggle">▼</span>
            </div>
            <div id="workloads" class="section-content">
                <h3 style="margin-bottom: 15px; font-size: 18px;">Deployments ($DEPLOY_COUNT)</h3>
EOF

  if [ "$DEPLOY_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
                <table>
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Status</th>
                            <th>Replicas</th>
                            <th>Available</th>
                            <th>Tolerations</th>
                        </tr>
                    </thead>
                    <tbody>
EOF
    jq -r '.[] | "<tr><td><code>\(.namespace)/\(.name)</code></td><td>\(if .healthy then "<span class=\"status-dot green\"></span><span class=\"badge success\">Healthy</span>" else "<span class=\"status-dot red\"></span><span class=\"badge error\">Unhealthy</span>" end)</td><td>\(.ready_replicas)/\(.replicas)</td><td>\(.available_replicas)</td><td>\(if .tolerations | length > 0 then ([.tolerations[] | "<code>\(.key // "*"):\(.effect)</code>"] | join(", ")) else "-" end)</td></tr>"' "$TEMP_DIR/deployments.json" >> "$OUTPUT_FILE"
    echo "                    </tbody>" >> "$OUTPUT_FILE"
    echo "                </table>" >> "$OUTPUT_FILE"
  else
    echo "                <div class=\"empty-state\"><div class=\"empty-state-icon\">📭</div><p>No deployments</p></div>" >> "$OUTPUT_FILE"
  fi

  # StatefulSets
  cat >> "$OUTPUT_FILE" << EOF

                <h3 style="margin-top: 30px; margin-bottom: 15px; font-size: 18px;">StatefulSets ($STS_COUNT)</h3>
EOF

  if [ "$STS_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
                <table>
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Status</th>
                            <th>Replicas</th>
                            <th>Volumes</th>
                        </tr>
                    </thead>
                    <tbody>
EOF
    jq -r '.[] | "<tr><td><code>\(.namespace)/\(.name)</code></td><td>\(if .healthy then "<span class=\"status-dot green\"></span><span class=\"badge success\">Healthy</span>" else "<span class=\"status-dot red\"></span><span class=\"badge error\">Unhealthy</span>" end)</td><td>\(.ready_replicas)/\(.replicas)</td><td>\(.volume_claim_templates | map("\(.name) (\(.size))") | join(", "))</td></tr>"' "$TEMP_DIR/statefulsets.json" >> "$OUTPUT_FILE"
    echo "                    </tbody>" >> "$OUTPUT_FILE"
    echo "                </table>" >> "$OUTPUT_FILE"
  else
    echo "                <div class=\"empty-state\"><div class=\"empty-state-icon\">📭</div><p>No StatefulSets</p></div>" >> "$OUTPUT_FILE"
  fi

  # CronJobs
  cat >> "$OUTPUT_FILE" << EOF

                <h3 style="margin-top: 30px; margin-bottom: 15px; font-size: 18px;">CronJobs ($CRON_COUNT)</h3>
EOF

  if [ "$CRON_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
                <table>
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Schedule</th>
                            <th>Suspended</th>
                            <th>Active</th>
                            <th>Last Run</th>
                        </tr>
                    </thead>
                    <tbody>
EOF
    jq -r '.[] | "<tr><td><code>\(.namespace)/\(.name)</code></td><td><code>\(.schedule)</code></td><td>\(if .suspend then "<span class=\"badge warning\">Yes</span>" else "<span class=\"badge success\">No</span>" end)</td><td>\(.active)</td><td>\(.last_schedule // "Never")</td></tr>"' "$TEMP_DIR/cronjobs.json" >> "$OUTPUT_FILE"
    echo "                    </tbody>" >> "$OUTPUT_FILE"
    echo "                </table>" >> "$OUTPUT_FILE"
  else
    echo "                <div class=\"empty-state\"><div class=\"empty-state-icon\">📭</div><p>No CronJobs</p></div>" >> "$OUTPUT_FILE"
  fi

  cat >> "$OUTPUT_FILE" << 'EOF'
            </div>
        </div>
EOF

  # Pods section
  cat >> "$OUTPUT_FILE" << EOF
        <div class="section">
            <div class="section-header" onclick="toggleSection('pods')">
                <h2>📊 All Pods ($TOTAL_PODS)</h2>
                <span class="toggle">▼</span>
            </div>
            <div id="pods" class="section-content">
EOF

  jq -r '.[] | "<p style=\"margin-bottom: 15px;\"><strong>\(.namespace)</strong> - \(.total) pods | \(.running) running | \(.with_sidecar) with sidecar</p><table><thead><tr><th>Pod Name</th><th>Status</th><th>Ready</th><th>Containers</th><th>Sidecar</th><th>Restarts</th><th>Node</th></tr></thead><tbody>" + (.pods[] | "<tr><td><code>\(.name)</code></td><td>\(if .phase == "Running" then "<span class=\"badge success\">\(.phase)</span>" else "<span class=\"badge warning\">\(.phase)</span>" end)</td><td>\(if .ready then "<span class=\"badge success\">✅</span>" else "<span class=\"badge error\">❌</span>" end)</td><td>\(.ready_containers)/\(.container_count)</td><td>\(if .has_sidecar then "<span class=\"badge success\">✅</span>" else "<span class=\"badge error\">❌</span>" end)</td><td>\(.restart_count)</td><td><code>\(.node_name // "N/A")</code></td></tr>") + "</tbody></table>\(if .problems | length > 0 then "<div class=\"alert warning\" style=\"margin-top: 15px;\"><strong>⚠️ Problem Pods:</strong><ul style=\"margin-left: 20px; margin-top: 10px;\">" + (.problems | map("<li><code>\(.name)</code>: \(.reason) (restarts: \(.restart_count))</li>") | join("")) + "</ul></div>" else "" end)<br>"' "$TEMP_DIR/pod_health.json" >> "$OUTPUT_FILE"

  cat >> "$OUTPUT_FILE" << 'EOF'
            </div>
        </div>
EOF

  # Footer
  cat >> "$OUTPUT_FILE" << 'EOF'
        <div class="footer">
            <p>Generated by AKS Cluster Discovery Script</p>
            <p style="margin-top: 5px;"><a href="#" onclick="window.print(); return false;" class="no-print" style="color: #667eea;">Print Report</a></p>
        </div>
    </div>

    <script>
        function toggleSection(id) {
            const content = document.getElementById(id);
            const header = content.previousElementSibling;
            const toggle = header.querySelector('.toggle');
            
            if (content.classList.contains('collapsed')) {
                content.classList.remove('collapsed');
                toggle.textContent = '▼';
            } else {
                content.classList.add('collapsed');
                toggle.textContent = '▶';
            }
        }
    </script>
</body>
</html>
EOF

  echo ""
  echo "HTML report: $OUTPUT_FILE"
  
else
  # JSON output
  if [ -n "$TARGET_NAMESPACE" ]; then
    OUTPUT_FILE="$OUTPUT_DIR/${CLUSTER_NAME}_${TARGET_NAMESPACE}_${TIMESTAMP}.json"
  else
    OUTPUT_FILE="$OUTPUT_DIR/${CLUSTER_NAME}_${TIMESTAMP}.json"
  fi
  
  jq -n \
    --arg cluster "$CLUSTER_NAME" \
    --arg namespace "$TARGET_NAMESPACE" \
    --arg version "$CLUSTER_VERSION" \
    --slurpfile pools "$TEMP_DIR/pools.json" \
    --slurpfile namespaces "$TEMP_DIR/namespaces.json" \
    --slurpfile istio "$TEMP_DIR/istio.json" \
    --slurpfile deployments "$TEMP_DIR/deployments.json" \
    --slurpfile statefulsets "$TEMP_DIR/statefulsets.json" \
    --slurpfile cronjobs "$TEMP_DIR/cronjobs.json" \
    --slurpfile daemonsets "$TEMP_DIR/daemonsets.json" \
    --slurpfile pod_health "$TEMP_DIR/pod_health.json" \
    --slurpfile hpa "$TEMP_DIR/hpa.json" \
    --slurpfile pdb "$TEMP_DIR/pdb.json" \
    --slurpfile pvc "$TEMP_DIR/pvc.json" \
    '{
      cluster: $cluster,
      target_namespace: $namespace,
      version: $version,
      node_pools: $pools[0],
      namespaces: $namespaces[0],
      istio: $istio[0],
      workloads: {
        deployments: $deployments[0],
        statefulsets: $statefulsets[0],
        cronjobs: $cronjobs[0],
        daemonsets: $daemonsets[0]
      },
      pod_health: $pod_health[0],
      autoscaling: {
        hpa: $hpa[0],
        pdb: $pdb[0]
      },
      storage: {
        pvcs: $pvc[0]
      }
    }' > "$OUTPUT_FILE"
  
  echo ""
  echo "JSON report: $OUTPUT_FILE"
fi

echo ""