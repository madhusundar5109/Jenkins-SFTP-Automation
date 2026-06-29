# Jenkins Push-Based File Sync Pipeline

> **Event-driven file synchronization using `inotifywait` + Jenkins CI + SCP**  
> Any file dropped into a monitored folder is automatically transferred to a remote server — zero polling, zero manual triggers.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Setup Guide](#setup-guide)
  - [1. Install inotify-tools](#1-install-inotify-tools)
  - [2. Configure the Watcher Script](#2-configure-the-watcher-script)
  - [3. Create the systemd Service](#3-create-the-systemd-service)
  - [4. Configure Jenkins Credentials](#4-configure-jenkins-credentials)
  - [5. Create the Jenkins Pipeline](#5-create-the-jenkins-pipeline)
  - [6. Generate a Jenkins API Token](#6-generate-a-jenkins-api-token)
  - [7. First-Run Bootstrap](#7-first-run-bootstrap)
- [Testing](#testing)

---

## Overview

This pipeline solves a common DevOps requirement: **automatically sync files from a source server to a remote server the moment they are written**, without any polling mechanism or manual Jenkins triggers.

The solution is built on three independently operating layers:

| Layer | Component | Role |
|---|---|---|
| OS Watcher | `inotifywait` (systemd service) | Detects file events at kernel level instantly |
| HTTP Trigger | `curl` + Jenkins REST API | Pushes the filename as a parameter to Jenkins |
| CI Pipeline | Jenkins + `sshpass` + `scp` | Transfers the exact file to the remote host |

**Key design principle:** Jenkins never polls. It only wakes up when the watcher pushes a trigger — making this a true push-based pipeline.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SOURCE SERVER                            │
│                                                                 │
│   /home/client/sftp-test-client/   ◄── Any file dropped here   │
│              │                                                  │
│              │ kernel inotify event (close_write / moved_to)   │
│              ▼                                                  │
│   ┌─────────────────────┐                                       │
│   │  inotifywait -m     │  (systemd: file-watcher.service)      │
│   │  persistent daemon  │                                       │
│   └──────────┬──────────┘                                       │
│              │ curl POST /buildWithParameters?CHANGED_FILE=...  │
│              ▼                                                  │
│   ┌─────────────────────┐                                       │
│   │   Jenkins CI        │  http://<Jenkins_url>          │
│   │   Project-SFTP-Test │                                       │
│   └──────────┬──────────┘                                       │
│              │ sshpass + scp                                    │
└──────────────┼──────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│                       REMOTE SERVER                             │
│   <Remote server ip Address>:/home/remote/test-sftp-server/                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## How It Works

1. **A file is written or moved** into `/home/client/sftp-test-client/` on the source server
2. **Linux kernel fires** an `inotify` event (`close_write` or `moved_to`)
3. **`inotifywait` captures** the filename and passes it to the watcher loop
4. **`curl` POSTs** to the Jenkins REST API with `CHANGED_FILE` set to the full file path
5. **Jenkins receives** `HTTP 201 Created` and queues the build immediately
6. **Validate stage** confirms `CHANGED_FILE` is non-empty
7. **Transfer stage** uses `sshpass + scp` to push the file to the remote server
8. **Build completes** — watcher resumes watching for the next event

> **Works for any filename, any extension, any size.** No configuration change needed per file.

---

## Prerequisites

| Component | Version | Notes |
|---|---|---|
| Jenkins | latest | Running on port `8081` |
| Oracle Linux / RHEL | any | Agent node OS |
| `inotify-tools` | Any | Provides `inotifywait` |
| `sshpass` | Any | Required for password-based SCP |
| `curl` | Any | For Jenkins REST API trigger |
| Jenkins API Token | — | User > Configure > API Token |
| Jenkins Credential | `jenkins-sftp-key` | Username + Password type |

---

## Project Structure

```
├── watch.sh                   # Persistent file watcher script
├── file-watcher.service       # systemd unit file
├── Jenkinsfile                # Jenkins pipeline definition
└── README.md                  # This file
```

---

## Setup Guide

### 1. Install inotify-tools

```bash
# Oracle Linux / RHEL / CentOS
sudo yum install inotify-tools -y

# Ubuntu / Debian
sudo apt install inotify-tools -y

# Verify
which inotifywait
```

---

### 2. Configure the Watcher Script

Copy `watch.sh` to the Jenkins agent and update the variables:

```bash
sudo mkdir -p /opt/file-watcher
sudo cp watch.sh /opt/file-watcher/watch.sh
sudo chmod +x /opt/file-watcher/watch.sh
```

Edit the variables inside `watch.sh`:

```bash
SOURCE_FOLDER="/home/client/sftp-test-client/"   # Folder to watch
JENKINS_URL="<Jenkins url"          # Jenkins server URL
JENKINS_JOB="<Jenkins job>"                # Exact Jenkins job name
JENKINS_USER="<Jenkins user>"                             # Jenkins username
JENKINS_TOKEN="<your-api-token>"                  # Jenkins API token (see step 6)
```

**`watch.sh` contents:**

```bash
#!/bin/bash

SOURCE_FOLDER="/home/client/sftp-test-client/"
JENKINS_URL="<Jenkins url>"
JENKINS_JOB="<Jenkins job>"
JENKINS_USER="<Jenkins user>"
JENKINS_TOKEN="<your-api-token>"

inotifywait -m -e close_write,moved_to --format '%f' -q "$SOURCE_FOLDER" \
  | while read FILENAME; do
      FILEPATH="${SOURCE_FOLDER}${FILENAME}"
      echo "[watcher] Detected: $FILEPATH"

      curl -s -X POST \
        "${JENKINS_URL}/job/${JENKINS_JOB}/buildWithParameters?CHANGED_FILE=${FILEPATH}" \
        --user "${JENKINS_USER}:${JENKINS_TOKEN}"

      echo "[watcher] Triggered Jenkins for: $FILEPATH"
  done
```

---

### 3. Create the systemd Service

Copy `file-watcher.service` to the systemd directory:

```bash
sudo cp file-watcher.service /etc/systemd/system/file-watcher.service
```

**`file-watcher.service` contents:**

```ini
[Unit]
Description=File watcher - push trigger to Jenkins on file change
After=network.target

[Service]
ExecStart=/opt/file-watcher/watch.sh
Restart=always
RestartSec=5
User=client
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable file-watcher
sudo systemctl start file-watcher
sudo systemctl status file-watcher
```

---

### 4. Configure Jenkins Credentials

In Jenkins UI, add a credential for the remote SFTP server:

```
Manage Jenkins → Credentials → System → Global credentials → Add Credentials

Kind:     Username with password
ID:       jenkins-sftp-key
Username: <remote server SSH user>
Password: <remote server SSH password>
```

---

### 5. Create the Jenkins Pipeline

Create a new **Pipeline** job named `Project-SFTP-Test` in Jenkins and use the `Jenkinsfile`:


---

### 6. Generate a Jenkins API Token

1. Log in to Jenkins → click your **username** (top-right)
2. Click **Configure** in the left sidebar
3. Scroll to **API Token** → click **Add new Token**
4. Name it `file-watcher-token` → click **Generate**
5. **Copy the token immediately** — Jenkins will never show it again
6. Paste it into the `JENKINS_TOKEN` variable in `watch.sh`

> **Verify the token works:**
> ```bash
> curl -s -u "<Jenkins username>:<your-token>" <Jenkins url>/me/api/json
> ```

---

### 7. First-Run Bootstrap

Jenkins parameterized jobs require **one manual build** before the parameter is registered. Do this once:

```
Jenkins UI → Project-SFTP-Test → Build with Parameters
CHANGED_FILE: /tmp/bootstrap
→ Click Build
```

After this single manual run, every subsequent trigger from the watcher works fully automatically.

---

## Testing

### Step 1 — Test inotifywait directly

Open two terminals on the Jenkins agent:

```bash
# Terminal 1 — start the watcher
inotifywait -m -e close_write,moved_to --format '%f' -q /home/client/sftp-test-client/

# Terminal 2 — drop a test file
echo "test" > /home/client/sftp-test-client/testfile.txt
```

**Expected output in Terminal 1:**
```
testfile.txt
```

---

### Step 2 — Test the Jenkins curl trigger manually

```bash
curl -v -X POST \
    "<Jenkins_url>/job/<jobname>/buildWithParameters?CHANGED_FILE=/home/client/sftp-test-client/test.sh" \
    --user "<Jenkins user>:<your-token>"

# Expected: HTTP/1.1 201 Created
```

---

### Step 3 — Full end-to-end test

```bash
# Drop any file into the source folder
cp sample.pdf /home/client/sftp-test-client/


# Verify the file arrived on the remote server
ssh client@<remote_server> 'ls -la /home/remote/test-sftp-server/'
```

---




*Built and maintained by S. Madhu
