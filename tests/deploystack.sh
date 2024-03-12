#! /bin/bash
#
# Deploy podman stack
#
# Compose file
DOCKER_COMPOSE=${DOCKER_COMPOSE:=podman-compose.yaml}

# Images
SNAKEMAKE_IMAGE=${SNAKEMAKE_IMAGE:=quay.io/biocontainers/snakemake:7.32.4--hdfd78af_1}
HTCONDORIMAGE=${HTCONDORIMAGE:=docker.io/htcondor/mini:23.0-el8}

podman pull $SNAKEMAKE_IMAGE
podman pull $HTCONDORIMAGE

# Stack and service config
STACK_NAME=cookiecutter-htcondor
HTCONDOR_SERVICE=${STACK_NAME}_htcondor
SNAKEMAKE_SERVICE=${STACK_NAME}_snakemake
LOCAL_USER_ID=$(id -u)

##############################
## Functions
##############################

### Check if service is up
function service_up {
    SERVICE=$1
    COUNT=1
    MAXCOUNT=30

    podman service ps $SERVICE --format "{{.CurrentState}}" 2>/dev/null | grep Running
    service_up=$?

    until [ $service_up -eq 0 ]; do
	echo "$COUNT: service $SERVICE unavailable"
	sleep 5
	podman service ps $SERVICE --format "{{.CurrentState}}" 2>/dev/null | grep Running
	service_up=$?
	if [ $COUNT -eq $MAXCOUNT ]; then
	    echo "service $SERVICE not found; giving up"
	    exit 1
	fi
	COUNT=$((COUNT+1))
    done

    echo "service $SERVICE up!"
}


##############################
## Deploy stack
##############################

# Check if podman stack has been deployed
podman service ps $HTCONDOR_SERVICE --format "{{.CurrentState}}" 2>/dev/null | grep Running
service_up=$?

if [ $service_up -eq 1 ]; then
    podman play kube $DOCKER_COMPOSE;
fi

service_up $HTCONDOR_SERVICE
service_up $SNAKEMAKE_SERVICE
CONTAINER=$(podman ps | grep cookiecutter-htcondor_htcondor | awk '{print $1}')

# Fix snakemake header to point to /opt/local/bin
podman exec $CONTAINER /bin/bash -c "head -1 /opt/local/bin/snakemake" | grep -q "/usr/local/bin"
if [ $? -eq 0 ]; then
    echo "Rewriting snakemake header to point to /opt/local/bin"
    podman exec $CONTAINER /bin/bash -c 'sed -i -e "s:/usr:/opt:" /opt/local/bin/snakemake'
fi

# Add htcondor to snakemake
CONTAINER=$(podman ps | grep cookiecutter-htcondor_snakemake | awk '{print $1}')
podman exec $CONTAINER 'pip install htcondor && ldd --version' 
