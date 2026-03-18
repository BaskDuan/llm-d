# Graceful Shutdown for vLLM Model Services

## Overview

Starting with vLLM v0.18.0, the `--shutdown-timeout` parameter enables graceful shutdown of vLLM inference servers during pod termination. This feature minimizes user traffic disruption during Model Service upgrades by allowing in-flight requests to complete before the server terminates.

## Configuration

### vLLM Shutdown Timeout

Add the `--shutdown-timeout` parameter to your vLLM serve command:

```yaml
args:
  - "--shutdown-timeout=30"  # Wait up to 30 seconds for requests to complete
```

The timeout value (in seconds) determines how long vLLM will wait for in-flight requests to complete before forcefully shutting down.

### Kubernetes Termination Grace Period

Set `terminationGracePeriodSeconds` to a value **greater than** your `--shutdown-timeout`:

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 60  # Must be > shutdown-timeout
```

This ensures Kubernetes doesn't force-kill the pod before vLLM's graceful shutdown completes.

## How It Works

When a pod receives a termination signal (e.g., during a rolling update):

1. Kubernetes sends SIGTERM to the vLLM process
2. vLLM stops accepting new requests
3. vLLM waits up to `--shutdown-timeout` seconds for in-flight requests to complete
4. After timeout or when all requests complete, vLLM exits
5. If vLLM hasn't exited after `terminationGracePeriodSeconds`, Kubernetes sends SIGKILL

```text
Pod Termination Signal
      ↓
[vLLM receives SIGTERM]
      ↓
Stop accepting new requests
      ↓
[Wait for in-flight requests]
  ↓ (up to --shutdown-timeout seconds)
  ✓ All requests complete OR timeout reached
      ↓
vLLM exits gracefully
      ↓
[Kubernetes waits up to terminationGracePeriodSeconds]
      ↓
Pod terminated
```

## Benefits

- **Minimizes traffic disruption** - In-flight requests complete successfully
- **Predictable upgrade behavior** - Operators know exactly how long upgrades will take
- **Better user experience** - No failed requests during deployments
- **Safe rolling updates** - Pods terminate cleanly without dropping connections

## Example Configurations

### Basic Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-d-model-server
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
        - name: vllm
          command: ["/bin/bash", "-c"]
          args:
            - exec vllm serve --port 8000 --shutdown-timeout 30
```

### Helm Values (ModelService)

```yaml
decode:
  containers:
    - name: "vllm"
      modelCommand: vllmServe
      args:
        - "--shutdown-timeout=30"
```

Note: The `terminationGracePeriodSeconds` is typically configured at the helm chart level in the actual ModelService helm charts (see [llm-d-modelservice](https://github.com/llm-d-incubation/llm-d-modelservice)).

### Prefill/Decode Disaggregation

For disaggregated serving, configure both prefill and decode pods:

```yaml
decode:
  containers:
    - name: "vllm"
      args:
        - "--shutdown-timeout=30"

prefill:
  containers:
    - name: "vllm"
      args:
        - "--shutdown-timeout=30"
```

## Recommended Values

| Configuration | Recommended Value | Notes |
| ------------- | ----------------- | ----- |
| `--shutdown-timeout` | 30 seconds | Allows most requests to complete |
| `terminationGracePeriodSeconds` | 60 seconds | 30s buffer above shutdown-timeout |

Adjust these values based on your workload:

- **Longer timeouts** for workloads with long-running requests (e.g., large context windows, high token counts)
- **Shorter timeouts** for workloads with quick requests (e.g., small models, low token counts)

## Monitoring

Monitor graceful shutdown behavior using:

### Pod Events

```bash
kubectl get events -n llm-d --field-selector involvedObject.name=<pod-name>
```

Look for events indicating:
- Pod termination started
- Container exit codes (0 = graceful shutdown)

### vLLM Logs

```bash
kubectl logs -n llm-d <pod-name> -c vllm --tail=50
```

Look for shutdown-related log messages indicating:
- Shutdown signal received
- Waiting for requests to complete
- Graceful shutdown completed

### Metrics

Monitor these metrics during rolling updates:

- Request failure rate (should remain low)
- Request latency (should remain stable)
- Pod termination duration (should be < terminationGracePeriodSeconds)

## Troubleshooting

### Pods Taking Too Long to Terminate

**Symptom:** Pods remain in `Terminating` state for the full `terminationGracePeriodSeconds`.

**Possible causes:**
- Requests taking longer than `--shutdown-timeout`
- vLLM not responding to SIGTERM
- Deadlock or hung process

**Solutions:**
- Increase `--shutdown-timeout` if requests legitimately need more time
- Check vLLM logs for errors or warnings
- Verify vLLM version supports `--shutdown-timeout` (v0.18.0+)

### Requests Still Failing During Updates

**Symptom:** Some requests fail with connection errors during rolling updates.

**Possible causes:**
- `--shutdown-timeout` too short
- Load balancer not respecting pod readiness
- New pods not ready before old pods terminate

**Solutions:**
- Increase `--shutdown-timeout`
- Configure proper readiness probes (see [readiness-probes.md](./readiness-probes.md))
- Adjust rolling update strategy (e.g., `maxUnavailable: 0`)

### Force-Killed Pods

**Symptom:** Pods show exit code 137 (SIGKILL) in logs.

**Possible causes:**
- `terminationGracePeriodSeconds` too short
- `terminationGracePeriodSeconds` ≤ `--shutdown-timeout`

**Solutions:**
- Increase `terminationGracePeriodSeconds` to be at least 30s greater than `--shutdown-timeout`
- Verify configuration is applied correctly

## Version Requirements

- **vLLM:** v0.18.0 or later
- **Kubernetes:** Any version (uses standard pod lifecycle)

## References

- [vLLM PR #34730](https://github.com/vllm-project/vllm/pull/34730) - Original implementation
- [GitHub Issue #927](https://github.com/llm-d/llm-d/issues/927) - Feature request
- [Kubernetes Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination)
- [llm-d Readiness Probes](./readiness-probes.md)

## Related Documentation

- [Readiness Probes](./readiness-probes.md) - Configure health checks for vLLM pods
- [Monitoring Guide](./monitoring/README.md) - Monitor vLLM performance and health
- [Getting Started](./getting-started-inferencing.md) - Basic inference setup
