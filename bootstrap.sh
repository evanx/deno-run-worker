#!/bin/bash
set -eu

INPUT_SECRET=`cat` # beware that env vars are leaky

trap 'echo "TRAP ERR LINENO=${LINENO}"' ERR

WORKER_CLASS="${1}"
redis-cli type "${WORKER_CLASS}:h" | grep -q '^hash$'
redis-cli hexists "${WORKER_CLASS}:h" workerCount | grep -q '^0$'

WORKER_REPO=`redis-cli hget ${WORKER_CLASS}:h repo`
WORKER_CLASS=`redis-cli hget ${WORKER_CLASS}:h class`
WORKER_VERSION=`redis-cli hget ${WORKER_CLASS}:h version`

echo ${WORKER_CLASS} | grep -q '^[a-z][-a-z0-9_]*$'
if [ "${WORKER_VERSION}" = 'local' ]
then
  echo "local development"
  WORKER_REPO=${LOCAL_WORKER_REPO}
  echo "${WORKER_REPO}" | grep -q "^/"
  [ -f ${WORKER_REPO}/${WORKER_CLASS}/worker.ts ]
elif [ "${WORKER_VERSION}" = 'main' ]
then
  echo "main branch"
elif echo ${WORKER_VERSION} | grep -q '^v[0-9]\.[0-9]\.[0-9]$'
then
  echo "tag ${WORKER_VERSION}"
fi
echo "worker setup OK: class ${WORKER_CLASS}"

redis-cli hexists ${WORKER_CLASS}:h startedCount | grep -q '^0$'
redis-cli hset ${WORKER_CLASS}:h startedCount 0
redis-cli hset ${WORKER_CLASS}:h pid ${$}

while [ 1 ]
do
  length=`redis-cli llen ${WORKER_CLASS}:start:q`
  echo "${length}" | grep -q '^[0-9]$' 
  echo "Start queue length: ${length}"
  if [ "${length}" -eq 0 ]
  then
    sleep 8
    continue
  fi
  (
    workerId=`redis-cli lmove ${WORKER_CLASS}:start:q ${WORKER_CLASS}:started:q right left`
    echo "${workerId}" | grep -q '^[1-9]$'
    echo "Worker ${workerId}:" consumerId `
      redis-cli hget ${WORKER_CLASS}:${workerId}:h consumerId
    `
    echo "${INPUT_SECRET}" | deno run --allow-net=127.0.0.1:6379 --allow-run ./main.ts \
      ${WORKER_REPO} ${WORKER_CLASS} ${WORKER_VERSION} ${workerId} ||
      echo "ERROR ${WORKER_CLASS} ${WORKER_VERSION} ${workerId}"
    redis-cli hdel ${WORKER_CLASS}:${workerId}:h pid | grep '^[0-1]$'
    redis-cli lrem ${WORKER_CLASS}:started:q 1 ${workerId} | grep -q '^1$' || 
      echo "WARN lrem ${WORKER_CLASS}:started:q 1 ${workerId}"
    redis-cli lpush ${WORKER_CLASS}:start:q ${workerId} | grep -q '^[1-9]$' ||
      echo "WARN lpush ${WORKER_CLASS}:started:q ${workerId}"
  ) &
  sleep 1
done
