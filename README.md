# VM Idle Shutdown Monitor

A lightweight, automated systemd-based daemon to monitor a virtual machine's CPU load and active user sessions, automatically triggering a clean system shutdown when the VM remains idle beyond a configurable threshold. 

This is highly effective for cost optimization, preventing idle cloud VMs from running and billing continuously when not in use.

> **Authorship note:** I used AI to help develop significant portions of this repository, including parts of the implementation and documentation. I reviewed, tested, and refined that content before including it here.

---

## How It Works

The system utilizes a lightweight bash script scheduled via a **Systemd Timer** to periodically check system activity. 

```mermaid
flowchart LR
    Start([Timer Triggers]) --> Check{System Idle?<br>CPU low & 0 sessions}
    Check -- Yes --> Increment[Increment Idle Counter]
    Check -- No --> Reset[Reset Counter to 0]
    
    Increment --> Limit{Counter >= IDLE_LIMIT?}
    Limit -- Yes --> Shutdown([Trigger Poweroff])
    Limit -- No --> End([Exit])
    Reset --> End
```

1. **CPU Monitoring**: Checks the 5-minute CPU load average from `/proc/loadavg`.
2. **Session Monitoring**: Verifies active interactive shell sessions (`ssh`, `bash`, `sh` or `pts` allocations).
3. **Threshold Check**: If both CPU usage is below the configured threshold AND no user sessions are active, it increments a persistent idle counter stored in `/run/vm_idle_time`.
4. **Action**: If the counter reaches the `IDLE_LIMIT`, the system triggers `systemctl poweroff`. If any activity is detected before the limit is reached, the idle counter resets to `0`.

---

## File Structure

* **`idle-shutdown.sh`**: The core shell script that performs system checks, tracks idle duration, and executes the shutdown command.
* **`units/`**: Contains the systemd configuration units.
  * **`idle-shutdown.service`**: The systemd oneshot service configuration.
  * **`idle-shutdown.timer`**: The systemd timer that periodically triggers the idle-shutdown service.
* **`local/`**: Contains the local environment simulation/sandbox harness.
  * **`Dockerfile`**: A Debian Bookworm environment configured with systemd to simulate, test, and debug the setup locally inside a container.
  * **`run-test.sh`**: A shell utility to automatically build, run, and provide commands for inspecting the test container.

---

## Configuration

You can customize the thresholds and schedules in two distinct locations:

### 1. Script Parameters (Idle Thresholds)
Located at the top of [idle-shutdown.sh](file:///home/aefiguerola/projects/idle-shutdown/idle-shutdown.sh):

```bash
# Thresholds
CPU_THRESHOLD=0.10  # Maximum CPU average load (5-min) considered idle
IDLE_LIMIT=600      # Total idle duration in seconds before triggering shutdown (600s = 10 mins)
IDLE_FILE="/run/vm_idle_time"  # State file to track accumulated idle time
```

### 2. Systemd Timer Parameters (Execution Schedules)
Located in [units/idle-shutdown.timer](file:///home/aefiguerola/projects/idle-shutdown/units/idle-shutdown.timer):

```ini
[Timer]
OnBootSec=10min       # Time to wait after system boot before the first check
OnUnitActiveSec=1min  # How often the check runs after that (once per minute)
```

---

## How the Timing Math Works (& Gotchas)

Understanding the relationship between the **Systemd Timer** and the **Bash Script Counter** is crucial to avoid unexpected behavior or extremely delayed shutdowns.

### The Active Setup (Checks run every 1 minute)
Here is the step-by-step timeline of how the currently configured parameters interact:

| Time Elapsed | Event | What Happens | Counter Value | VM State |
|---|---|---|---|---|
| **0 - 10 min** | System bootup | System stabilizes; **no checks run**. | `0s` | Online |
| **10 min** | Boot countdown ends | First check runs. If idle, adds `60s`. | `60s` | Online |
| **11 min** | 1 min active timer | Second check runs. If still idle, adds `60s`. | `120s` | Online |
| **...** | ... | ... | ... | ... |
| **20 min** | 10th consecutive check | Tenth check runs. If idle, adds `60s`. Hits `600s` limit! | `600s` | **Shutdown!** |

> [!TIP]  
> If CPU load spikes or you log in during **any** of the checks from minutes 10 to 19, the script instantly resets the counter to `0`. The 10-minute continuous idle countdown starts all over.

---

### ⚠️ The "4.6-Hour Mismatch" Gotcha
A common mistake when configuring this system is mismatched timer execution frequency (e.g. running the check once every 30 minutes) versus the script's internal tick rate (which assumes `+60` seconds of idle credit per run).

**The Mismatch Example:**
* **`OnUnitActiveSec = 30min`** (Timer check runs every 30 minutes)
* **`IDLE_LIMIT = 600`** (Script expects 10 minutes / 600s of idle time)
* **`NEW_IDLE = CURRENT_IDLE + 60`** (Script adds 60s per check)

**Why it's a gotcha:**
Because the check only runs once every 30 minutes, it takes **10 successful checks** to reach the 600-second limit. 
* **Mathematically**: `10 checks * 30 minutes = 300 minutes (5 hours)` of continuous, absolute idleness to finally trigger a shutdown!
* **The Risk**: If a minor CPU spike happens at minute 270 (after 4.5 hours of idleness), the counter drops to `0`, and you must wait another 5 hours.

---

### Customizing for Common Use Cases

#### Case 1: You want a 30-minute idle shutdown (with frequent checking)
If you want the VM to shut down after exactly 30 minutes of continuous idleness:
1. **In `units/idle-shutdown.timer`**: Keep `OnUnitActiveSec=1min` (checks run once a minute).
2. **In `idle-shutdown.sh`**: Change `IDLE_LIMIT=1800` (1800 seconds = 30 minutes).

#### Case 2: You want a 1-hour idle shutdown (with frequent checking)
If you want the VM to shut down after exactly 60 minutes of continuous idleness:
1. **In `units/idle-shutdown.timer`**: Keep `OnUnitActiveSec=1min`.
2. **In `idle-shutdown.sh`**: Change `IDLE_LIMIT=3600` (3600 seconds = 60 minutes).

---

## Production Deployment

To deploy this monitoring system on your VM, follow these steps:

### 1. Install Files to System Pathways
Copy the files into their corresponding system directories and make the script executable:

```bash
# Copy the script
sudo cp idle-shutdown.sh /usr/local/bin/idle-shutdown.sh
sudo chmod +x /usr/local/bin/idle-shutdown.sh

# Copy Systemd units
sudo cp units/idle-shutdown.service /etc/systemd/system/idle-shutdown.service
sudo cp units/idle-shutdown.timer /etc/systemd/system/idle-shutdown.timer
```

### 2. Enable and Start the Timer
Reload the systemd daemon configurations and enable the timer unit:

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable and start the timer immediately
sudo systemctl enable --now idle-shutdown.timer
```

### 3. Verify the Status
Confirm the timer is active and scheduled to run:

```bash
# Check the timer status
sudo systemctl status idle-shutdown.timer

# View active timers on the system
systemctl list-timers --all | grep idle-shutdown
```

---

## Local Testing & Docker Simulation

This project includes a Docker-based test harness that boots a full Debian system running systemd, allowing you to safely test the script's behavior and systemd unit bindings without powering down your host machine.

### Prerequisites
- Docker installed on your host machine.
- User privileges to run docker (or `sudo` access).

### Run the Test Suite
Simply run the test runner script from the repository root:

```bash
./local/run-test.sh
```

This script will:
1. Stop and remove any previous test containers.
2. Build the Docker image containing systemd, our script, and service configurations.
3. Launch the container running systemd as PID 1 with required capabilities (`SYS_ADMIN`).

### Useful Commands for Debugging

* **Check the Status of the Timer inside the Container**:
  ```bash
  docker exec -it local-systemd-box systemctl status idle-shutdown.timer
  ```

* **Tail Script Execution Logs in Real-time**:
  ```bash
  docker exec -it local-systemd-box journalctl -u idle-shutdown.service -f
  ```

* **Manually Trigger a Check**:
  ```bash
  docker exec -it local-systemd-box systemctl start idle-shutdown.service
  ```

* **Clean Up the Test Container**:
  ```bash
  docker stop local-systemd-box && docker rm local-systemd-box
  ```

---

## ⚠️ Important Considerations

> [!WARNING]  
> If you are active in a SSH session on your VM, the script will detect your session under `ACTIVE_SESSIONS` and will **not** shutdown. However, as soon as you disconnect or if your terminal session times out, the active session count drops to `0`. If CPU load is also under `0.10`, the counter will begin ticking towards the shutdown limit. Ensure your session timeout settings and idle shutdown timer durations are aligned to prevent unexpected shutdowns while you are still working.

---

## License

This project is licensed under the MIT License - see the [LICENSE](file:///home/aefiguerola/projects/idle-shutdown/LICENSE) file for details.
