#!/usr/bin/env bash
set -e

log() {
  echo ">> [local]" $@
}

cleanup() {
  set +e
  log "Killing ssh agent."
  ssh-agent -k
  log "Removing workspace archive."
  rm -f /tmp/workspace.tar.bz2
}
trap cleanup EXIT

log "Packing workspace into archive to transfer onto remote machine."
tar cjvf /tmp/workspace.tar.bz2 --exclude .git --exclude vendor .

log "Launching ssh agent."
eval `ssh-agent -s`

# Build docker compose command with optional profile and env-file
PROFILE_ARG=""
if [ -n "$DOCKER_COMPOSE_PROFILES" ]; then
  PROFILE_ARG="--profile $DOCKER_COMPOSE_PROFILES"
fi

ENV_FILE_ARG=""
if [ -n "$DOCKER_COMPOSE_ENV_FILE" ]; then
  ENV_FILE_ARG="--env-file $DOCKER_COMPOSE_ENV_FILE"
fi

COMPOSE_CMD="docker compose $ENV_FILE_ARG -f \"$DOCKER_COMPOSE_FILENAME\" $PROFILE_ARG -p \"$DOCKER_COMPOSE_PREFIX\""

remote_command="set -e ; log() { echo '>> [remote]' \$@ ; } ; cleanup() { log 'Removing workspace...'; rm -rf \"\$HOME/workspace\" ; } ; log 'Creating workspace directory...' ; mkdir -p \"\$HOME/workspace\" ; trap cleanup EXIT ; log 'Unpacking workspace...' ; tar -C \"\$HOME/workspace\" -xjv ; log 'Launching docker compose...' ; cd \"\$HOME/workspace\" ; $COMPOSE_CMD pull ; $COMPOSE_CMD up -d --remove-orphans --build"

if $USE_DOCKER_STACK ; then
  remote_command="set -e ; log() { echo '>> [remote]' \$@ ; } ; cleanup() { log 'Removing workspace...'; rm -rf \"\$HOME/workspace\" ; } ; log 'Creating workspace directory...' ; mkdir -p \"\$HOME/workspace/$DOCKER_COMPOSE_PREFIX\" ; trap cleanup EXIT ; log 'Unpacking workspace...' ; tar -C \"\$HOME/workspace/$DOCKER_COMPOSE_PREFIX\" -xjv ; log 'Launching docker stack deploy...' ; cd \"\$HOME/workspace/$DOCKER_COMPOSE_PREFIX\" ; docker stack deploy -c \"$DOCKER_COMPOSE_FILENAME\" --prune \"$DOCKER_COMPOSE_PREFIX\""
fi

if $DOCKER_COMPOSE_DOWN ; then
  remote_command="set -e ; log() { echo '>> [remote]' \$@ ; } ; cleanup() { log 'Removing workspace...'; rm -rf \"\$HOME/workspace\" ; } ; log 'Creating workspace directory...' ; mkdir -p \"\$HOME/workspace\" ; trap cleanup EXIT ; log 'Unpacking workspace...' ; tar -C \"\$HOME/workspace\" -xjv ; log 'Launching docker compose...' ; cd \"\$HOME/workspace\" ; $COMPOSE_CMD down"
fi

ssh-add <(echo "$SSH_PRIVATE_KEY")

echo ">> [local] Connecting to remote host."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$SSH_HOST" -p "$SSH_PORT" \
  "$remote_command" \
  < /tmp/workspace.tar.bz2