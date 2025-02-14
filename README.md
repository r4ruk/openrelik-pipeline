# openrelik-pipeline

## Ubuntu deployment

### Step 1 - Install Docker 
```bash
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg -y
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo apt-get install docker-compose -y
```

### Step 2 - Deploy Timesketch and create an admin user
```bash
cd /opt
curl -s -O https://raw.githubusercontent.com/google/timesketch/master/contrib/deploy_timesketch.sh
chmod 755 deploy_timesketch.sh
sudo env START_CONTAINER=Y SKIP_CREATE_USER=1 ./deploy_timesketch.sh
docker compose exec timesketch-web tsctl create-user admin 
```

### Step 3 - Deploy OpenRelik
```bash
curl -s -O https://raw.githubusercontent.com/openrelik/openrelik-deploy/main/docker/install.sh # Modify this if you want
bash install.sh
```
> [!NOTE]  
> This will generate an `admin` user and password. The password will be displayed when the deployment is complete. Be sure to save it.


### Step 4 - Deploy OpenRelik Timesketch worker
Append the following to your `docker-compose.yml`:
```bash
echo "

  openrelik-worker-timesketch:
    container_name: openrelik-worker-timesketch
    image: ghcr.io/openrelik/openrelik-worker-timesketch:\${OPENRELIK_WORKER_TIMESKETCH_VERSION}
    restart: always
    environment:
      - REDIS_URL=redis://openrelik-redis:6379
      - TIMESKETCH_SERVER_URL=http://YOUR_TIMESKETCH_IP
      - TIMESKETCH_SERVER_PUBLIC_URL=http://YOUR_TIMESKETCH_IP
      - TIMESKETCH_USERNAME=YOUR_TIMESKETCH_USER
      - TIMESKETCH_PASSWORD=YOUR_TIMESKETCH_PASSWORD
    volumes:
      - ./data:/usr/share/openrelik/data
    command: \"celery --app=src.app worker --task-events --concurrency=1 --loglevel=INFO -Q openrelik-worker-timesketch\"
" | sudo tee -a ./openrelik/docker-compose.yml > /dev/null

```
Then start it:
```bash
docker compose up -d
```

### Step 5 - Verify deployment
```bash
docker ps -a
```
If you see the Prometheus container failing to start, you can try `chmod 777 openrelik/data/prometheus`.  

Log in at `http://localhost:8711`

### Step 6 - Generate an API key
1. Click the user icon in the top right corner
2. Click `API keys`
3. Click `Create API key`
4. Provide a name, click `Create`, copy the key, and save it for Step 7 


### Step 7 - Start the pipeline
```bash
git clone https://github.com/shortstack/openrelik-pipeline.git /opt/openrelik-pipeline
cd /opt/openrelik-pipeline
pip3 install -r requirements.txt
export OPENRELIK_API_KEY=YOUR_API_KEY
python3 main.py
```  

This will start a local server on `http://localhost:5000`.  

You can now send files to it for processing and timelining:

```bash
curl -X POST -F "file=@/path/to/your/file.zip" -F "filename=file.zip" http://localhost:5000/api/plaso/upload

curl -X POST -F "file=@/path/to/your/file.zip" -F "filename=file.zip" http://localhost:5000/api/hayabusa/upload

```

  
------------------------------
> [!IMPORTANT]  
> **I strongly recommend deploying OpenRelik and Timesketch with HTTPS**--additional instructions for Timesketch and OpenRelik are provided [here](https://github.com/google/timesketch/blob/master/docs/guides/admin/install.md#4-enable-tls-optional) and [here](https://github.com/openrelik/openrelik.org/blob/main/content/guides/nginx.md). For this proof of concept, we're using HTTP. Modify your configs to reflect HTTPS if you deploy for production use. 