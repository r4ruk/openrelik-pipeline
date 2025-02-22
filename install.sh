#!/bin/bash

# Set working directory to /opt
cd /opt || exit 1

# Deploy Timesketch
curl -s -O https://raw.githubusercontent.com/google/timesketch/master/contrib/deploy_timesketch.sh
chmod 755 deploy_timesketch.sh
./deploy_timesketch.sh <<EOF
Y
N
EOF

# Change directory to timesketch
cd timesketch || exit 1

# Create Timesketch user
echo -e "${TIMESKETCH_PASSWORD}\n${TIMESKETCH_PASSWORD}" | \
  docker compose exec -T timesketch-web tsctl create-user "$TIMESKETCH_USER"

# Deploy OpenRelik
cd /opt || exit 1
curl -s -O https://raw.githubusercontent.com/openrelik/openrelik-deploy/main/docker/install.sh

# Run the installation script and capture output
script_output="$(bash install.sh 2>&1)"

# Strip ANSI escape codes
stripped_output="$(echo "$script_output" | sed 's/\x1B\[[0-9;]*[A-Za-z]//g')"

# Extract password from output
password="$(echo "$stripped_output" | grep '^Password:' | awk '{print $2}')"
if [ -n "$password" ]; then
  export OPENRELIK_PASSWORD="$password"
  echo "Your username is admin and your password is $OPENRELIK_PASSWORD"
else
  echo "Could not find a 'Password:' line in the script output."
fi

# Set proper permissions for OpenRelik
chmod 777 openrelik/data/prometheus
sleep 10

# Configure OpenRelik
cd /opt/openrelik || exit 1
docker compose down
sed -i 's/127\.0\.0\.1/0\.0\.0\.0/g' /opt/openrelik/docker-compose.yml
sed -i "s/localhost/$IP_ADDRESS/g" /opt/openrelik/config.env
sed -i "s/localhost/$IP_ADDRESS/g" /opt/openrelik/config/settings.toml
docker compose up -d

# Deploy OpenRelik Timesketch worker
echo "

  openrelik-worker-timesketch:
    container_name: openrelik-worker-timesketch
    image: ghcr.io/openrelik/openrelik-worker-timesketch:\${OPENRELIK_WORKER_TIMESKETCH_VERSION}
    restart: always
    environment:
      - REDIS_URL=redis://openrelik-redis:6379
      - TIMESKETCH_SERVER_URL=http://timesketch-web:5000
      - TIMESKETCH_SERVER_PUBLIC_URL=http://$IP_ADDRESS
      - TIMESKETCH_USERNAME=$TIMESKETCH_USER
      - TIMESKETCH_PASSWORD=$TIMESKETCH_PASSWORD
    volumes:
      - ./data:/usr/share/openrelik/data
    command: \"celery --app=src.app worker --task-events --concurrency=1 --loglevel=INFO -Q openrelik-worker-timesketch\"
" | sudo tee -a ./docker-compose.yml > /dev/null

docker network connect openrelik_default timesketch-web
docker compose up -d

