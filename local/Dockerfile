FROM docker.io/library/debian:bookworm-slim

# 1. Install systemd, math engine (bc), and process tracker (procps)
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd \
    systemd-sysv \
    bc \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Copy your automation files to their correct system pathways
COPY idle-shutdown.sh /usr/local/bin/idle-shutdown.sh
COPY units/idle-shutdown.service /etc/systemd/system/idle-shutdown.service
COPY units/idle-shutdown.timer /etc/systemd/system/idle-shutdown.timer

# 3. Correct execution permissions and enable the systemd timer module
RUN chmod +x /usr/local/bin/idle-shutdown.sh && \
    systemctl enable idle-shutdown.timer

# 4. Set systemd as the absolute entrypoint execution manager
CMD ["/lib/systemd/systemd"]
