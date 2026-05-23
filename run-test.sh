#!/usr/bin/env bash

# Exit immediately if any command fails
set -e

CONTAINER_NAME="local-systemd-box"
IMAGE_NAME="shutdown-test-image"

echo "=== 1. Cleaning up previous test instances ==="
if sudo docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "Found old container. Stopping and removing..."
    sudo docker stop "$CONTAINER_NAME" || true
    sudo docker rm "$CONTAINER_NAME" || true
fi

echo -e "\n=== 2. Building the minimal systemd container image ==="
sudo docker build -t "$IMAGE_NAME" .

echo -e "\n=== 3. Launching the systemd test box in the background ==="
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --cap-add=SYS_ADMIN \
  --security-opt label=disable \
  "$IMAGE_NAME"

echo -e "\n========================================================="
echo " SUCCESS: Test box is running with systemd active."
echo "========================================================="
echo " To inspect the live systemd timer queue, run:"
echo "   sudo docker exec -it $CONTAINER_NAME systemctl status idle-shutdown.timer"
echo -e "\n To tail your script execution logs in real-time, run:"
echo "   sudo docker exec -it $CONTAINER_NAME journalctl -u idle-shutdown.service -f"
echo -e "\n When finished, drop into the container or wipe it with:"
echo "   sudo docker stop $CONTAINER_NAME && sudo docker rm $CONTAINER_NAME"
echo "========================================================="
