#!/bin/bash
set -euo pipefail

# ============================================================
# Employee Directory - EC2 Bootstrap
# ============================================================

# Log everything to both console and file.
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

trap 'echo "ERROR: bootstrap failed on line $LINENO"' ERR

echo "============================================================"
echo "Starting Employee Directory bootstrap"
echo "Date: $(date)"
echo "============================================================"

# ------------------------------------------------------------
# Install required packages
# ------------------------------------------------------------
# Amazon Linux 2023 minimal already includes curl-minimal, which provides
# the curl command. Avoid installing the full curl package during bootstrap.

echo "===== Installing required packages ====="

dnf install -y \
    python3 \
    python3-pip \
    unzip \
    wget

# Optional load-testing tool. Do not fail the application bootstrap if the
# package is unavailable.
dnf install -y stress || echo "WARNING: stress package not available - continuing"

# ------------------------------------------------------------
# Install and start AWS Systems Manager Agent
# ------------------------------------------------------------
# SSM is useful for troubleshooting but must never prevent the application
# from starting. The selected AL2023 minimal AMI may not include the agent.

echo "===== Configuring SSM Agent ====="

if ! rpm -q amazon-ssm-agent >/dev/null 2>&1; then
    echo "SSM Agent is not installed. Installing from the regional AWS RPM..."
    dnf install -y \
        "https://s3.${aws_region}.amazonaws.com/amazon-ssm-${aws_region}/latest/linux_amd64/amazon-ssm-agent.rpm" \
        || echo "WARNING: SSM Agent installation failed - continuing application bootstrap"
fi

systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl restart amazon-ssm-agent 2>/dev/null || true
systemctl status amazon-ssm-agent --no-pager || true

# ------------------------------------------------------------
# Create application directory
# ------------------------------------------------------------

echo "===== Preparing application directory ====="

mkdir -p /opt/employee-directory
cd /opt/employee-directory

# ------------------------------------------------------------
# Download Flask application
# ------------------------------------------------------------

echo "===== Downloading Flask application ====="

wget -q \
    https://aws-tc-largeobjects.s3-us-west-2.amazonaws.com/DEV-AWS-MO-GCNv2/FlaskApp.zip \
    -O FlaskApp.zip

# ------------------------------------------------------------
# Extract application
# ------------------------------------------------------------

echo "===== Extracting Flask application ====="

rm -rf FlaskApp
unzip -o FlaskApp.zip
cd FlaskApp

printf '%s\n' "===== Application files ====="
ls -la

# ------------------------------------------------------------
# Install Python dependencies
# ------------------------------------------------------------

echo "===== Installing Python dependencies ====="

python3 -m pip install --no-cache-dir -r requirements.txt

# ------------------------------------------------------------
# Create environment file
# ------------------------------------------------------------

echo "===== Creating environment file ====="

cat > /etc/employee-directory.env <<EOF_ENV
PHOTOS_BUCKET=${photos_bucket}
AWS_DEFAULT_REGION=${aws_region}
DYNAMO_MODE=on
FLASK_APP=application.py
PYTHONUNBUFFERED=1
EOF_ENV

chmod 600 /etc/employee-directory.env

# ------------------------------------------------------------
# Create systemd service
# ------------------------------------------------------------

echo "===== Creating Flask systemd service ====="

cat > /etc/systemd/system/employee-directory.service <<'EOF_SERVICE'
[Unit]
Description=Employee Directory Flask Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/employee-directory/FlaskApp
EnvironmentFile=/etc/employee-directory.env
ExecStart=/usr/bin/python3 -m flask run --host=0.0.0.0 --port=80
Restart=always
RestartSec=5
User=root
StandardOutput=append:/var/log/flask.log
StandardError=append:/var/log/flask.log

[Install]
WantedBy=multi-user.target
EOF_SERVICE

# ------------------------------------------------------------
# Start Flask application
# ------------------------------------------------------------

echo "===== Starting Employee Directory service ====="

systemctl daemon-reload
systemctl enable employee-directory.service
systemctl restart employee-directory.service

# ------------------------------------------------------------
# Wait for the local application to become healthy
# ------------------------------------------------------------

echo "===== Waiting for Flask application ====="

APP_READY=false

for attempt in {1..30}; do
    if curl --silent --show-error --fail --max-time 5 http://127.0.0.1:80/ >/dev/null; then
        APP_READY=true
        echo "Employee Directory responded successfully on attempt $attempt."
        break
    fi

    echo "Application not ready yet (attempt $attempt/30)."
    sleep 5
done

# ------------------------------------------------------------
# Diagnostics
# ------------------------------------------------------------

echo "===== Employee Directory service status ====="
systemctl status employee-directory.service --no-pager || true

echo "===== Listening ports ====="
ss -lntp || true

echo "===== Flask log ====="
cat /var/log/flask.log || true

echo "===== Local HTTP test ====="
curl -v --connect-timeout 5 --max-time 10 http://127.0.0.1:80/ || true

echo "===== SSM Agent final status ====="
systemctl status amazon-ssm-agent --no-pager || true

if [ "$APP_READY" != "true" ]; then
    echo "ERROR: Employee Directory did not return HTTP 200 within 150 seconds."
    exit 1
fi

echo "============================================================"
echo "Bootstrap completed successfully"
echo "Date: $(date)"
echo "============================================================"
