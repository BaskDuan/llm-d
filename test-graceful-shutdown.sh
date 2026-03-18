#!/bin/bash
set -e

echo "=== Testing vLLM Graceful Shutdown Feature ==="
echo ""

# Configuration
MODEL="facebook/opt-125m"  # Small model for quick testing
CONTAINER_NAME="vllm-test-shutdown"
PORT=8000
SHUTDOWN_TIMEOUT=30

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Step 1: Cleaning up any existing containers${NC}"
docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
sleep 2

echo ""
echo -e "${YELLOW}Step 2: Starting vLLM server with --shutdown-timeout=${SHUTDOWN_TIMEOUT}${NC}"
docker run -d \
  --name ${CONTAINER_NAME} \
  -p ${PORT}:${PORT} \
  --ipc=host \
  vllm/vllm-openai:latest \
  --model ${MODEL} \
  --port ${PORT} \
  --shutdown-timeout ${SHUTDOWN_TIMEOUT} \
  --max-model-len 512 \
  --gpu-memory-utilization 0.3

echo "Container started: ${CONTAINER_NAME}"
echo ""

echo -e "${YELLOW}Step 3: Waiting for vLLM to be ready...${NC}"
MAX_WAIT=120
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  if curl -s http://localhost:${PORT}/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ vLLM is ready!${NC}"
    break
  fi
  echo -n "."
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  echo -e "${RED}✗ Timeout waiting for vLLM to start${NC}"
  docker logs ${CONTAINER_NAME}
  docker rm -f ${CONTAINER_NAME}
  exit 1
fi

echo ""
echo -e "${YELLOW}Step 4: Testing /v1/models endpoint${NC}"
curl -s http://localhost:${PORT}/v1/models | jq '.' || echo "Failed to get models"

echo ""
echo -e "${YELLOW}Step 5: Starting concurrent requests in background${NC}"
# Start multiple long-running requests
for i in {1..5}; do
  (
    echo "Request $i: Starting..."
    START_TIME=$(date +%s)
    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:${PORT}/v1/completions \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${MODEL}\",
        \"prompt\": \"Write a long story about artificial intelligence: \",
        \"max_tokens\": 200,
        \"temperature\": 0.7
      }" 2>&1)
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    FINISH_REASON=$(echo "$RESPONSE" | jq -r '.choices[0].finish_reason' 2>/dev/null || echo "error")
    
    echo "Request $i: Completed in ${DURATION}s, HTTP: ${HTTP_CODE}, finish_reason: ${FINISH_REASON}"
  ) &
done

echo "Started 5 concurrent requests"
sleep 3

echo ""
echo -e "${YELLOW}Step 6: Sending SIGTERM to container (simulating pod deletion)${NC}"
SHUTDOWN_START=$(date +%s)
docker kill --signal=SIGTERM ${CONTAINER_NAME}
echo "SIGTERM sent at $(date)"

echo ""
echo -e "${YELLOW}Step 7: Monitoring shutdown process...${NC}"
echo "Waiting for requests to complete (up to ${SHUTDOWN_TIMEOUT}s)..."

# Wait for all background jobs
wait

SHUTDOWN_END=$(date +%s)
SHUTDOWN_DURATION=$((SHUTDOWN_END - SHUTDOWN_START))

echo ""
echo -e "${GREEN}=== Test Results ===${NC}"
echo "Shutdown duration: ${SHUTDOWN_DURATION}s"
echo "Configured timeout: ${SHUTDOWN_TIMEOUT}s"

if [ $SHUTDOWN_DURATION -le $((SHUTDOWN_TIMEOUT + 10)) ]; then
  echo -e "${GREEN}✓ Shutdown completed within expected time${NC}"
else
  echo -e "${RED}✗ Shutdown took longer than expected${NC}"
fi

echo ""
echo -e "${YELLOW}Step 8: Checking container logs${NC}"
echo "Last 30 lines of logs:"
docker logs --tail 30 ${CONTAINER_NAME}

echo ""
echo -e "${YELLOW}Step 9: Cleanup${NC}"
docker rm -f ${CONTAINER_NAME} 2>/dev/null || true

echo ""
echo -e "${GREEN}=== Test Complete ===${NC}"
