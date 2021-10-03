#!/bin/bash
set -eu

INPUT_SECRET=`cat` # beware that env vars are leaky

trap 'echo "ERROR `basename ${0}` LINENO=${LINENO}"' ERR

WORKER_TYPE="${1}"
redis-cli type "${WORKER_TYPE}:h" | grep -q '^hash$'
redis-cli hexists "${WORKER_TYPE}:h" workerCount | grep -q '^0$'

WORKER_URL=`redis-cli hget ${WORKER_TYPE}:h workerUrl`
WORKER_TYPE=`redis-cli hget ${WORKER_TYPE}:h workerType`
WORKER_VERSION=`redis-cli hget ${WORKER_TYPE}:h workerVersion`

echo ${WORKER_TYPE} | grep -q '^[a-z][-a-z0-9_]*$'
if [ "${WORKER_VERSION}" = 'local' ]
then
  echo "local development: ${WORKER_URL}"
  echo "${WORKER_URL}" | grep -q "^/.*/worker\.ts$"
  [ -f "${WORKER_URL}" ]
elif [ "${WORKER_VERSION}" = 'main' ]
then
  echo "main branch"
elif echo ${WORKER_VERSION} | grep -q '^v[0-9]\.[0-9]\.[0-9]$'
then
  echo "tag ${WORKER_VERSION}"
fi
echo "worker setup OK: ${WORKER_TYPE}"

redis-cli hexists ${WORKER_TYPE}:h startedCount | grep -q '^0$'
redis-cli hset ${WORKER_TYPE}:h startedCount 0
redis-cli hset ${WORKER_TYPE}:h pid ${$}

while [ 1 ]
do
  length=`redis-cli llen ${WORKER_TYPE}:start:q`
  echo "${length}" | grep -q '^[0-9]$' 
  echo "Start queue length: ${length}"
  if [ "${length}" -eq 0 ]
  then
    sleep 8
    continue
  fi
  (
    workerId=`redis-cli lmove ${WORKER_TYPE}:start:q ${WORKER_TYPE}:started:q right left`
    echo "${workerId}" | grep -q '^[1-9]$'
    WORKER_KEY="${WORKER_TYPE}:${workerId}:h"
    echo "Worker ${workerId}:" consumerId `
      redis-cli hget ${WORKER_KEY} consumerId
    `
    echo "${INPUT_SECRET}" | deno run --allow-net=127.0.0.1:6379 --allow-run ./main.ts \
      ${WORKER_URL} ${WORKER_KEY} ||
      echo "ERROR ${WORKER_URL} ${WORKER_KEY}"
    redis-cli hdel ${WORKER_KEY} pid | grep '^[0-1]$'
    redis-cli lrem ${WORKER_TYPE}:started:q 1 ${workerId} | grep -q '^1$' || 
      echo "WARN lrem ${WORKER_TYPE}:started:q 1 ${workerId}"
    redis-cli lpush ${WORKER_TYPE}:start:q ${workerId} | grep -q '^[1-9]$' ||
      echo "WARN lpush ${WORKER_TYPE}:started:q ${workerId}"
  ) &
  sleep 1
done
