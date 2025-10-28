#!/bin/bash

SERVER_IP="13.62.102.225" 
SSH_KEY="~/.ssh/hng-key.pem"
#this variables here are not industry standard and are not best practices to store server IPs and key files

echo "Setting up Stage 2 deployment on $SERVER_IP"

# Transfer project
scp -i $SSH_KEY -r ~/Projects/stage2-devops ubuntu@$SERVER_IP:~/

# Setup server
ssh -i $SSH_KEY ubuntu@$SERVER_IP << 'EOF'
  # Install Docker
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker ubuntu
  
  # Install Docker Compose
  sudo apt-get install docker-compose-plugin -y
  
  echo "Setup complete! Re-login to use Docker"
EOF

echo "Done! Now SSH in and start services:"
echo "ssh -i $SSH_KEY ubuntu@$SERVER_IP"
echo "cd ~/stage2-devops"
echo "docker compose up -d"
