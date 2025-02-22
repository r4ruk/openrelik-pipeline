# openrelik-pipeline

### Intro
This repository provides an all-in-one DFIR solution by deploying Timesketch, OpenRelik, and the custom OpenRelik Pipeline tool via Docker Compose. It allows users to send forensic artifacts (e.g., Windows event logs or full triage acquisitions) to an API endpoint, which triggers a workflow to upload the files to OpenRelik and generate a timeline. Depending on the configuration, the workflow can use log2timeline (Plaso) or Hayabusa to produce the timeline and push it directly into Timesketch. This automated approach streamlines artifact ingestion and analysis, turning what used to be multiple separate processes into a more convenient, “push-button” deployment. 

### Notes
* There are PRs/issues to make some tweaks in some of the involved repos. 
    * [Ability to set the OpenRelik admin password via an environment variable](https://github.com/openrelik/openrelik-deploy/pull/11)
    * [Ability to create an OpenRelik API key without authing in the web UI](https://github.com/openrelik/openrelik-server/issues/62)
        * This is the main reason manual intervention is required right now and that this cannot be fully scripted. You must log into the OpenRelik web UI in order to generate an API key, and then manually update your `docker-compose.yml` file for the pipeline to work.
    * [Fix for generating a custom Timesketch sketch name vs an auto-generated name](https://github.com/openrelik/openrelik-worker-timesketch/pull/4)

------------------------------

### Step 1 - Install Docker 
Follow the official installation instructions to [install Docker Engine](https://docs.docker.com/engine/install/).

### Step 2 - Set environment variables 
```bash
sudo -i
export TIMESKETCH_USER="admin"
export TIMESKETCH_PASSWORD="YOUR_DESIRED_TIMESKETCH_PASSWORD"
export IP_ADDRESS="0.0.0.0" # Change this to your public IPv4 address if deploying on a cloud server
```

### Step 3 - Deploy Timesketch and create an admin user
Additional details can be found in the [Timesketch docs](https://timesketch.org/guides/admin/install/).
```bash
cd /opt
curl -s -O https://raw.githubusercontent.com/google/timesketch/master/contrib/deploy_timesketch.sh
chmod 755 deploy_timesketch.sh
./deploy_timesketch.sh <<EOF
Y
N
EOF
cd timesketch
echo -e "${TIMESKETCH_PASSWORD}\n${TIMESKETCH_PASSWORD}" | docker compose exec -T timesketch-web tsctl create-user $TIMESKETCH_USER
```

### Step 4 - Deploy OpenRelik
Additional details can be found in the [OpenRelik docs](https://openrelik.org/docs/getting-started/).

```bash
cd /opt
curl -s -O https://raw.githubusercontent.com/openrelik/openrelik-deploy/main/docker/install.sh 
script_output="$(bash install.sh 2>&1)"
stripped_output="$(echo "$script_output" | sed 's/\x1B\[[0-9;]*[A-Za-z]//g')"
password="$(echo "$stripped_output" | grep '^Password:' | awk '{print $2}')"
if [ -n "$password" ]; then
  export OPENRELIK_PASSWORD="$password"
  echo "Your username is admin and your password is $OPENRELIK_PASSWORD"
else
  echo "Could not find a 'Password:' line in the script output."
fi
chmod 777 openrelik/data/prometheus
```
> [!NOTE]  
> This will generate an `admin` user and password. The password will be displayed when the deployment is complete. Be sure to save it.

```bash
cd /opt/openrelik
docker compose down
sed -i 's/127\.0\.0\.1/0\.0\.0\.0/g' /opt/openrelik/docker-compose.yml
sed -i "s/localhost/$IP_ADDRESS/g" /opt/openrelik/config.env
sed -i "s/localhost/$IP_ADDRESS/g" /opt/openrelik/config/settings.toml
docker compose up -d
```

### Step 5 - Deploy OpenRelik Timesketch worker
Append the following to your `docker-compose.yml`, then link your Timesketch container to the `openrelik_default` network, and start it:

```bash
cd /opt/openrelik
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
```

### Step 6 - Verify deployment
```bash
docker ps -a
```

Log in at `http://0.0.0.0:8711` (or the IP you provided if deploying in the cloud).

### Step 7 - Generate an API key
1. Click the user icon in the top right corner
2. Click `API keys`
3. Click `Create API key`
4. Provide a name, click `Create`, copy the key, and save it for Step 8 


### Step 8 - Start the pipeline
Modify your API key in `docker-compose.yml`, then build and run the container.
```bash
git clone https://github.com/Digital-Defense-Institute/openrelik-pipeline.git /opt/openrelik-pipeline
cd /opt/openrelik-pipeline
sed -i 's/YOUR_API_KEY/$YOUR_ACTUAL_API_KEY/g' docker-compose.yml
docker compose build
docker compose up -d
docker network connect openrelik_default openrelik-pipeline
```

This will start the server on `http://0.0.0.0:5000` (or the IP you provided if deploying in the cloud).

### Step 9 - Send data
You can now send files to it for processing and timelining.

Generate a timeline with Hayabusa from your Windows event logs and push it into Timesketch:
```bash
curl -X POST -F "file=@/path/to/your/Security.evtx" -F "filename=Security.evtx" http://$IP_ADDRESS:5000/api/hayabusa/upload
```

Generate a timeline with Plaso and push it into Timesketch:
```bash
curl -X POST -F "file=@/path/to/your/triage.zip" -F "filename=triage.zip" http://$IP_ADDRESS:5000/api/plaso/upload
```

You can view your timelines at `http://0.0.0.0` (or the IP you provided if deploying in the cloud).
  
------------------------------
> [!IMPORTANT]  
> **I strongly recommend deploying OpenRelik and Timesketch with HTTPS**--additional instructions for Timesketch and OpenRelik are provided [here](https://github.com/google/timesketch/blob/master/docs/guides/admin/install.md#4-enable-tls-optional) and [here](https://github.com/openrelik/openrelik.org/blob/main/content/guides/nginx.md). For this proof of concept, we're using HTTP. Modify your configs to reflect HTTPS if you deploy for production use. 