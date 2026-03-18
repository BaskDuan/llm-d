# Graceful Shutdown 功能测试指南

本文档说明如何测试 vLLM 的 `--shutdown-timeout` 功能。

## 前置条件

1. Docker 或 Kubernetes 集群
2. vLLM v0.18.0+ 镜像

## 测试方法 1: 使用 Docker（推荐用于快速测试）

### 1. 启动 vLLM 服务器

```bash
docker run -d \
  --name vllm-shutdown-test \
  -p 8000:8000 \
  --ipc=host \
  vllm/vllm-openai:latest \
  --model facebook/opt-125m \
  --port 8000 \
  --shutdown-timeout 30 \
  --max-model-len 256 \
  --enforce-eager
```

### 2. 等待服务器启动

```bash
# 等待健康检查通过
while ! curl -s http://localhost:8000/health > /dev/null; do
  echo "Waiting for vLLM..."
  sleep 2
done
echo "vLLM is ready!"
```

### 3. 测试基本功能

```bash
# 测试 /v1/models 端点
curl http://localhost:8000/v1/models | jq '.'

# 发送一个简单的请求
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "facebook/opt-125m",
    "prompt": "Hello, ",
    "max_tokens": 10
  }' | jq '.'
```

### 4. 测试 Graceful Shutdown

在一个终端中启动长时间运行的请求：

```bash
# Terminal 1: 启动多个长请求
for i in {1..3}; do
  (
    echo "Request $i starting at $(date +%H:%M:%S)"
    curl -s http://localhost:8000/v1/completions \
      -H "Content-Type: application/json" \
      -d '{
        "model": "facebook/opt-125m",
        "prompt": "Write a long story: ",
        "max_tokens": 100
      }' > /tmp/request_$i.json
    echo "Request $i completed at $(date +%H:%M:%S)"
    cat /tmp/request_$i.json | jq -r '.choices[0].finish_reason'
  ) &
done
```

在另一个终端中发送 SIGTERM：

```bash
# Terminal 2: 等待 2 秒后发送 SIGTERM
sleep 2
echo "Sending SIGTERM at $(date +%H:%M:%S)"
docker kill --signal=SIGTERM vllm-shutdown-test
```

### 5. 观察结果

检查请求是否完成：

```bash
# 等待所有后台任务完成
wait

# 检查结果
for i in {1..3}; do
  echo "Request $i result:"
  cat /tmp/request_$i.json | jq -r '.choices[0].finish_reason'
done
```

预期结果：
- 在 SIGTERM 之前启动的请求应该完成（finish_reason: "length" 或 "stop"）
- 在 SIGTERM 之后的新请求应该被拒绝（HTTP 503 或连接错误）

### 6. 检查日志

```bash
docker logs vllm-shutdown-test 2>&1 | grep -i "shutdown\|sigterm"
```

应该看到类似的日志：
```
Received SIGTERM signal
Waiting for in-flight requests to complete (timeout: 30s)
Shutdown completed
```

### 7. 清理

```bash
docker rm -f vllm-shutdown-test
```

## 测试方法 2: 使用 Kubernetes

### 1. 应用配置

```bash
cd guides/recipes/vllm/base

# 修改 deployment.yaml，设置一个小模型用于测试
# 将 INFERENCE_SERVER_IMAGE 替换为实际镜像
kubectl apply -f deployment.yaml
```

### 2. 等待 Pod 就绪

```bash
kubectl wait --for=condition=ready pod -l llm-d.ai/inference-serving=true --timeout=300s
```

### 3. 端口转发

```bash
kubectl port-forward svc/llm-d-model-server 8000:8000 &
```

### 4. 发送测试请求

```bash
# 启动长时间运行的请求
for i in {1..5}; do
  (
    echo "Request $i starting"
    curl -s http://localhost:8000/v1/completions \
      -H "Content-Type: application/json" \
      -d '{
        "model": "facebook/opt-125m",
        "prompt": "Write a story: ",
        "max_tokens": 100
      }' > /tmp/k8s_request_$i.json
    echo "Request $i: $(cat /tmp/k8s_request_$i.json | jq -r '.choices[0].finish_reason')"
  ) &
done
```

### 5. 触发 Pod 删除（模拟滚动更新）

```bash
# 等待 2 秒后删除一个 pod
sleep 2
POD=$(kubectl get pods -l llm-d.ai/inference-serving=true -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod: $POD"
kubectl delete pod $POD
```

### 6. 观察 Pod 终止过程

```bash
# 在另一个终端监控 pod 状态
kubectl get pods -l llm-d.ai/inference-serving=true -w
```

预期行为：
- Pod 进入 Terminating 状态
- 等待最多 60 秒（terminationGracePeriodSeconds）
- 在 30 秒内（shutdown-timeout）完成请求后优雅退出

### 7. 检查 Pod 日志

```bash
kubectl logs $POD | grep -i "shutdown\|sigterm"
```

### 8. 验证请求结果

```bash
wait
for i in {1..5}; do
  echo "Request $i: $(cat /tmp/k8s_request_$i.json | jq -r '.choices[0].finish_reason')"
done
```

## 测试方法 3: 使用自动化脚本

我们提供了两个自动化测试脚本：

### 简单版本（推荐）

```bash
./test-graceful-shutdown-simple.sh
```

这个脚本会：
1. 启动 vLLM 容器（CPU 模式）
2. 发送测试请求
3. 在请求进行中发送 SIGTERM
4. 验证请求是否完成
5. 检查日志
6. 自动清理

### 完整版本

```bash
./test-graceful-shutdown.sh
```

这个脚本包含更详细的测试和验证。

## 预期结果

### 成功的 Graceful Shutdown 应该表现为：

1. **请求完成**：在 SIGTERM 之前启动的请求应该成功完成
   - `finish_reason` 应该是 "stop" 或 "length"，而不是 "abort"

2. **新请求被拒绝**：在 SIGTERM 之后的新请求应该被拒绝
   - HTTP 状态码：503 (Service Unavailable) 或 500
   - 或者连接被关闭

3. **超时控制**：整个关闭过程应该在配置的时间内完成
   - 实际关闭时间 ≤ shutdown-timeout + 几秒缓冲

4. **日志信息**：应该看到相关的关闭日志
   - "Received SIGTERM"
   - "Waiting for requests"
   - "Shutdown completed"

### 失败的情况（如果没有 graceful shutdown）：

1. 所有请求立即中止（finish_reason: "abort"）
2. 连接立即断开
3. 没有等待时间

## 故障排查

### 问题 1: 请求被立即中止

**可能原因**：
- vLLM 版本 < 0.18.0
- `--shutdown-timeout` 参数未生效
- `terminationGracePeriodSeconds` 太短

**解决方案**：
- 检查 vLLM 版本：`docker exec vllm-shutdown-test vllm --version`
- 检查启动参数：`docker inspect vllm-shutdown-test | jq '.[0].Args'`
- 增加 `terminationGracePeriodSeconds`

### 问题 2: Pod 被强制终止

**可能原因**：
- `terminationGracePeriodSeconds` ≤ `shutdown-timeout`
- Kubernetes 强制 SIGKILL

**解决方案**：
- 确保 `terminationGracePeriodSeconds` > `shutdown-timeout` + 30秒缓冲

### 问题 3: 关闭时间过长

**可能原因**：
- 请求处理时间超过 timeout
- 模型太大，生成太慢

**解决方案**：
- 增加 `--shutdown-timeout` 值
- 使用更小的模型进行测试
- 减少 `max_tokens`

## 参考文档

- [vLLM PR #34730](https://github.com/vllm-project/vllm/pull/34730)
- [llm-d Issue #927](https://github.com/llm-d/llm-d/issues/927)
- [Graceful Shutdown 文档](../docs/graceful-shutdown.md)
