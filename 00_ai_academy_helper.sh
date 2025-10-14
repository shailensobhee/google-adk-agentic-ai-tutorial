#!/bin/bash

# --- Configuration ---
VLLM_MODEL="meta-llama/Llama-3.1-8B-Instruct"
VLLM_PORT=8088
VLLM_TEMPLATE="vllm/examples/tool_chat_template_llama3.1_json.jinja"
OLLAMA_MODEL="llama3.1"
# --- End Configuration ---

# 1. Argument Handling (HF_TOKEN)
if [ -z "$1" ]; then
    echo "Error: HuggingFace Token (HF_TOKEN) is required as the first argument."
    echo "Usage: $0 <YOUR_HF_TOKEN>"
    exit 1
fi

export HF_TOKEN="$1"
echo "HF_TOKEN set for model downloads."

# --- Helper Functions ---

# Function to check if a process is running on a specific port
# Note: This is a basic check. A more robust solution might use a health check endpoint.
wait_for_port() {
    local port=$1
    local timeout=60 # seconds
    local counter=0
    echo "Waiting for server to start on port $port..."
    while ! lsof -i :$port -t > /dev/null; do
        sleep 1
        counter=$((counter + 1))
        if [ $counter -ge $timeout ]; then
            echo "Error: Timeout waiting for port $port."
            return 1
        fi
    done
    echo "Server is listening on port $port."
    return 0
}

# Function to clean up background jobs on exit/interrupt
cleanup() {
    echo "Stopping background servers (vLLM and Ollama)..."
    # Kill all background jobs started in this script's session
    kill $(jobs -p) 2>/dev/null
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup INT TERM EXIT

# --- vLLM Server Setup and Model Download ---

echo "--- Starting vLLM Server and downloading $VLLM_MODEL ---"

# The vLLM server will download the model if it's not present.
# It's started in the background (&) and its process ID is captured.
vllm serve "$VLLM_MODEL" \
    --enable-auto-tool-choice \
    --tool-call-parser llama3_json \
    --port "$VLLM_PORT" \
    --chat-template "$VLLM_TEMPLATE" > vllm_server.log 2>&1 &
VLLM_PID=$!
echo "vLLM server started (PID: $VLLM_PID). Output is being logged to vllm_server.log."

# Wait for vLLM to start and download the model.
# NOTE: The port check is *before* the model download completes in vLLM.
# For actual use, you'd need to poll a health endpoint (e.g., /metrics or /health).
# For now, we'll wait briefly for the process to be established.
sleep 5 # Give it a few seconds to start the process and begin downloading/loading

# --- Ollama Server Setup and Model Download ---

echo "--- Installing and Starting Ollama Server and downloading $OLLAMA_MODEL ---"

# 2. Install Ollama (if not installed)
if ! command -v ollama &> /dev/null; then
    echo "Ollama not found. Installing now..."
    # The curl script pipes directly to bash. This is standard for Ollama.
    curl -fsSL https://ollama.com/install.sh | bash
    if [ $? -ne 0 ]; then
        echo "Error: Ollama installation failed. Exiting."
        exit 1
    fi
else
    echo "Ollama is already installed."
fi

# 3. Start Ollama Server
ollama serve > ollama_server.log 2>&1 &
OLLAMA_PID=$!
echo "Ollama server started (PID: $OLLAMA_PID). Output is being logged to ollama_server.log."

# Ollama doesn't use a standard port in the same way, but it uses an API.
# Wait for it to be ready by trying to run a simple command.
echo "Waiting for Ollama service to become available..."
sleep 5 # Give it a few seconds to initialize

# 4. Download/Pull Ollama Model
echo "Pulling Ollama model: $OLLAMA_MODEL (This might take a while)..."
# The 'run' command will pull the model if it's not present and then run it.
# We just want to pull it, so we'll run it once and quit.
ollama run "$OLLAMA_MODEL" --verbose "hello"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download or run Ollama model '$OLLAMA_MODEL'. Exiting."
    exit 1
fi
echo "Ollama model $OLLAMA_MODEL is ready."

# --- Final State ---

echo "--- Servers are running (or starting) and models are downloaded ---"
echo "vLLM Server Status: Check 'vllm_server.log' for readiness."
echo "Ollama Server Status: Check 'ollama_server.log' for readiness."
echo ""
echo "Script is now paused. Press [Ctrl+C] to stop both servers gracefully."

# Keep the script running indefinitely until interrupted (Ctrl+C)
# This allows the background servers to continue running.
wait
