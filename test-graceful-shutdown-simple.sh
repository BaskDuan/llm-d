#!/bin/bash
set -e

echo "=== Testing vLLM Graceful Shutdown Feature (CPU Mode) ==="
echo ""

# Configuration
MODEL="facebook/opt-125m"  # Small model for quick testing
CONTAINER_NAME="vllm-test-shutdown"
PORT=8000
SHUTDOWN_TIMEOUT=10  # Shorter timeout for testing

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

cleanup() {
  echo ""
  echo -e "${YELLOW}Cleaning up...${NC}"
  docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
}

trap cleanup EXIT

echo -e "${YELLOW}Step 1: Cleaning up any existing containers${NC}"
docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
sleep 2

echo ""
echo -e "${YELLOW}Step 2: Starting vLLM server with --shutdown-timeout=${SHUTDOWN_TIMEOUT}${NC}"
echo "Command: vllm serve --model ${MODEL} --port ${PORT} --shutdown-timeout ${SHUTDOWN_TIMEOUT}"

docker run -d \
  --name ${CONTAINER_NAME} \
  -p ${PORT}:${PORT} \
  --ipc=host \
  vllm/vllm-openai:latest \
  --model ${MODEL} \
  --port ${PORT} \
  --shutdown-timeout ${SHUTDOWN_TIMEOUT} \
  --max-model-len 256 \
  --enforce-eager

echo "Container started: ${CONTAINER_NAME}"
echo ""

echo -e "${YELLOW}Step 3: Waiting for vLLM to be ready...${NC}"
MAX_WAIT=180
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  if curl -s http://localhost:${PORT}/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ vLLM is ready!${NC}"
    break
  fi
  echo -n "."
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  echo -e "${RED}✗ Timeout waiting for vLLM to start${NC}"
  echo "Container logs:"
  docker logs ${CONTAINER_NAME}
  exit 1
fi

echo ""
echo -e "${YELLOW}Step 4: Testing /v1/models endpoint${NC}"
MODELS=$(curl -s http://localhost:${PORT}/v1/models)
echo "$MODELS" | jq '.' 2>/dev/null || echo "$MODELS"

echo ""
echo -e "${YELLOW}Step 5: Sending a test request${NC}"
curl -s http://localhost:${PORT}/v1/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL}\",
    \"prompt\": \"Hello, \",
    \"max_tokens\": 10
  }" | jq '.' 2>/dev/null || echo "Request completed"

echo ""
echo -e "${YELLOW}Step 6: Starting long-running requests in background${NC}"
REQUEST_LOG="/tmp/vllm-test-requests.log"
> ${REQUEST_LOG}

for i in {1..3}; do
  (
    echo "[Request $i] Starting at $(date +%H:%M:%S)" | tee -a ${REQUEST_LOG}
    START_TIME=$(date +%s)
    
    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:${PORT}/v1/completions \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${MODEL}\",
        \"prompt\": \"Write a story: \",
        \"max_tokens\": 100,
        \"temperature\": 0.7
      }" 2>&1)
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    FINISH_REASON=$(echo "$RESPONSE" | jq -r '.choices[0].finish_reason' 2>/dev/null || echo "unknown")
    
    echo "[Request $i] Completed at $(date +%H:%M:%S), Duration: ${DURATION}s, HTTP: ${HTTP_CODE}, finish_reason: ${FINISH_REASON}" | tee -a ${REQUEST_LOG}
  ) &
done

echo "Started 3 concurrent requests"
sleep 2

echo ""
echo -e "${YELLOW}Step 7: Sending SIGTERM to container${NC}"
echo "This simulates a pod deletion during a rolling update"
SHUTDOWN_START=$(date +%s)
echo "SIGTERM sent at $(date +%H:%M:%S)"
docker kill --signal=SIGTERM ${CONTAINER_NAME}

echo ""
echo -e "${YELLOW}Step 8: Waiting for requests to complete...${NC}"
echo "Configured shutdown timeout: ${SHUTDOWN_TIMEOUT}s"

# Wait for all background jobs
wait

SHUTDOWN_END=$(date +%s)
SHUTDOWN_DURATION=$((SHUTDOWN_END - SHUTDOWN_START))

echo ""
echo -e "${GREEN}=== Test Results ===${NC}"
echo "Shutdown duration: ${SHUTDOWN_DURATION}s"
echo "Configured timeout: ${SHUTDOWN_TIMEOUT}s"

echo ""
echo "Request results:"
cat ${REQUEST_LOG}

if [ $SHUTDOWN_DURATION -le $((SHUTDOWN_TIMEOUT + 15)) ]; then
  echo -e "${GREEN}✓ Shutdown completed within expected time${NC}"
else
  echo -e "${YELLOW}⚠ Shutdown took longer than expected (may include request processing time)${NC}"
fi

echo ""
echo -e "${YELLOW}Step 9: Checking container logs for shutdown messages${NC}"
echo "Looking for shutdown-related messages:"
docker logs ${CONTAINER_NAME} 2>&1 | grep -i "shutdown\|sigterm\|graceful" || echo "No shutdown messages found"

echo ""
echo -e "${GREEN}=== Test Complete ===${NC}"
echo ""
echo "Summary:"
echo "- Shutdown timeout configured: ${SHUTDOWN_TIMEOUT}s"
echo "- Actual shutdown duration: ${SHUTDOWN_DURATION}s"
echo "- Check the request log above to see if requests completed gracefully"
