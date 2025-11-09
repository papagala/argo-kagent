# M3 Helm Chart

A Helm chart for deploying M3 (MIMIC-IV + MCP + Models) on Kubernetes.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Docker image built from the Dockerfile in the repository

## Building the Docker Image

Before deploying, build the Docker image:

```bash
# For SQLite-only (lite) version
docker build --target lite -t m3-mcp:latest .

# For BigQuery version
docker build --target bigquery -t m3-mcp:bigquery .
```

## Installing the Chart

To install the chart with the release name `m3`:

```bash
helm install m3 ./helm-charts/m3
```

To install with custom values:

```bash
helm install m3 ./helm-charts/m3 -f custom-values.yaml
```

## Configuration

The following table lists the configurable parameters of the M3 chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Image repository | `m3-mcp` |
| `image.tag` | Image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.stage` | Dockerfile stage to use (lite or bigquery) | `lite` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `3000` |
| `service.targetPort` | Container port | `3000` |
| `resources.limits.cpu` | CPU limit | `1000m` |
| `resources.limits.memory` | Memory limit | `1Gi` |
| `resources.requests.cpu` | CPU request | `500m` |
| `resources.requests.memory` | Memory request | `512Mi` |
| `env.backend` | M3 backend type | `sqlite` |
| `env.dbPath` | Database path in container | `/root/m3_data/databases/mimic_iv_demo.db` |
| `env.pythonUnbuffered` | Python unbuffered output | `"1"` |
| `namespace` | Kubernetes namespace | `default` |
| `persistence.enabled` | Enable persistent volume | `false` |
| `persistence.size` | Size of persistent volume | `5Gi` |
| `persistence.mountPath` | Mount path for data | `/root/m3_data` |

## Examples

### Using BigQuery Backend

Create a `bigquery-values.yaml`:

```yaml
image:
  tag: bigquery
  stage: bigquery

env:
  backend: bigquery

secrets:
  name: m3-secrets
  gcpServiceAccountKey: "<base64-encoded-service-account-json>"
```

Then install:

```bash
helm install m3 ./helm-charts/m3 -f bigquery-values.yaml
```

### Enabling Persistence

Create a `persistence-values.yaml`:

```yaml
persistence:
  enabled: true
  storageClass: "standard"
  size: 10Gi
```

Then install:

```bash
helm install m3 ./helm-charts/m3 -f persistence-values.yaml
```

## Uninstalling the Chart

To uninstall/delete the `m3` deployment:

```bash
helm uninstall m3
```

This command removes all the Kubernetes components associated with the chart and deletes the release.

## Upgrading

To upgrade the chart:

```bash
helm upgrade m3 ./helm-charts/m3
```

## License

MIT License - See LICENSE file for details.
