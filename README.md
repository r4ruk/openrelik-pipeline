# openrelik-pipeline

### Intro
This repository provides an all-in-one DFIR solution by deploying Timesketch, OpenRelik, Velociraptor, and the custom OpenRelik Pipeline tool via Docker Compose. It allows users to send forensic artifacts (e.g., Windows event logs or full triage acquisitions generated with Velociraptor) to an API endpoint, which triggers a workflow to upload the files to OpenRelik and generate a timeline. Depending on the configuration, the workflow can use log2timeline (Plaso) or Hayabusa to produce the timeline and push it directly into Timesketch. This automated approach streamlines artifact ingestion and analysis, turning what used to be multiple separate processes into a more convenient, “push-button” deployment. 

### Notes
* There are PRs/issues to make some tweaks in some of the involved repos. 
    * [Ability to set the OpenRelik admin password via an environment variable](https://github.com/openrelik/openrelik-deploy/pull/11)
    * [Ability to create an OpenRelik API key without authing in the web UI](https://github.com/openrelik/openrelik-server/issues/62)
        * This is the main reason manual intervention is required right now and that this cannot be fully scripted. You must log into the OpenRelik web UI in order to generate an API key, and then manually update your `docker-compose.yml` file for the pipeline to work.
    * [Fix for generating a custom Timesketch sketch name vs an auto-generated name](https://github.com/openrelik/openrelik-worker-timesketch/pull/4)

------------------------------

### Step 1 - Install Docker 
Follow the official installation instructions to [install Docker Engine](https://docs.docker.com/engine/install/).

### Step 2 - Set environment variables and run the install script to deploy Timesketch, OpenRelik, and Velociraptor
Depending on your connection, this can take 5-10 minutes.
```bash
sudo -i
git clone https://github.com/Digital-Defense-Institute/openrelik-pipeline.git /opt/openrelik-pipeline
export TIMESKETCH_USER="admin"
export TIMESKETCH_PASSWORD="YOUR_DESIRED_TIMESKETCH_PASSWORD"
export VELOCIRAPTOR_PASSWORD="YOUR_DESIRED_VELOCIRAPTOR_PASSWORD"
export IP_ADDRESS="0.0.0.0" # Change this to your public or IPv4 address if deploying on a cloud server, a VM, or WSL
chmod +x /opt/openrelik-pipeline/install.sh
/opt/openrelik-pipeline/install.sh 
```

> [!NOTE]  
> This will generate an OpenRelik `admin` user and password. The password will be displayed when the deployment is complete. Be sure to save it. Your Velociraptor and Timesketch usernames are `admin`, and the passwords are what you set above.

### Step 3 - Verify deployment
Verify that all containers are up and running.
```bash
docker ps -a
```

Access the web UIs:
* Velociraptor - https://0.0.0.0:8889
* Timesketch - http://0.0.0.0 
* OpenRelik - http://0.0.0.0:8711

Again, if deploying elsewhere, or on a VM, or with WSL, use the IP you used for `$IP_ADDRESS`

### Step 4 - Generate an API key
Within OpenRelik:
1. Click the user icon in the top right corner
2. Click `API keys`
3. Click `Create API key`
4. Provide a name, click `Create`, copy the key, and save it for Step 5 

### Step 5 - Start the pipeline
Modify your API key in `docker-compose.yml`, then build and run the container.
```bash
cd /opt/openrelik-pipeline
sed -i 's/YOUR_API_KEY/$YOUR_ACTUAL_API_KEY/g' docker-compose.yml
docker compose build
docker compose up -d
docker network connect openrelik_default openrelik-pipeline
```

This will start the server on `http://0.0.0.0:5000` (or the IP you provided if deploying on something other than localhost).

### Step 6 - Access 

#### With curl
You can now send files to it for processing and timelining.

We've provided an example with curl so it can be easily translated into anything else.

Generate a timeline with Hayabusa from your Windows event logs and push it into Timesketch:
```bash
curl -X POST -F "file=@/path/to/your/Security.evtx" -F "filename=Security.evtx" http://$IP_ADDRESS:5000/api/hayabusa/upload
```

Generate a timeline with Plaso and push it into Timesketch:
```bash
curl -X POST -F "file=@/path/to/your/triage.zip" -F "filename=triage.zip" http://$IP_ADDRESS:5000/api/plaso/upload
```

#### With Velociraptor
In the repo, we've provided several Velociraptor artifacts. Add them in the Velociraptor GUI in the `View Artifacts` section. 

These are configured to hit each available endpoint:
* `/api/plaso`
* `/api/plaso/timesketch`
* `/api/hayabusa`
* `/api/hayabusa/timesketch`

You can configure them to run automatically by going to `Server Events` in the Velociraptor GUI and adding them to the server event monitoring table. 

By default, they are configured to run when the `Windows.KapeFiles.Targets` artifact completes on an endpoint.



  
------------------------------
> [!IMPORTANT]  
> **I strongly recommend deploying OpenRelik and Timesketch with HTTPS**--additional instructions for Timesketch and OpenRelik are provided [here](https://github.com/google/timesketch/blob/master/docs/guides/admin/install.md#4-enable-tls-optional) and [here](https://github.com/openrelik/openrelik.org/blob/main/content/guides/nginx.md). For this proof of concept, we're using HTTP. Modify your configs to reflect HTTPS if you deploy for production use. 
