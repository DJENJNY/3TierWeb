#!/bin/bash
set -e  # Stop on errors

echo "Starting bootstrap process"

# Update and install Docker
sudo yum update -y
sudo yum install -y docker

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Pull and run Nginx container
sudo docker pull nginx

# Remove existing container if it exists
if [ "$(sudo docker ps -aq -f name=nginx-container)" ]; then
  sudo docker rm -f nginx-container
fi

# Run new container
sudo docker run --name nginx-container -p 8080:80 -d nginx

echo "Bootstrap completed"

