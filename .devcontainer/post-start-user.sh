
# Agentfactory dependencies
if [ ! -f /workspace/agentfactory/package.json ]; then
  mkdir -p /workspace/agentfactory
  echo '{"name":"agentfactory","version":"1.0.0","private":true}' > /workspace/agentfactory/package.json
fi
cd /workspace/agentfactory && npm install -y

npx -y @renseiai/create-agentfactory-app my-agent

cd my-agent

# cp .env.example .env.local
cat > .env.local << EOF
LINEAR_ACCESS_TOKEN=${LINEAR_ACCESS_TOKEN}
WORKER_API_URL=http://localhost:3000
WORKER_API_KEY=some-secret-key-you-choose
REDIS_URL=redis://localhost:6379
EOF

# Start Redis
sudo service redis-server start

# npm install -g pnpm@latest-10
# cd ./devcontainer
# ./post-start-user.sh
pnpm install && pnpm dev      # Start webhook server
# ngrok http 3000 # start grok
# create linear webhook with grok url
# cd agentfactory/my-agent && pnpm worker                   # Start local worker in another terminal
