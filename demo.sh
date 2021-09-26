#!/bin/bash
set -eu

INPUT_SECRET=`openssl rand 32 -hex`

echo "Repo ${WORKER_REPO:=https://raw.githubusercontent.com/evanx}"
echo "Class ${WORKER_CLASS:=deno-date-iso}"
echo "Secret ${INPUT_SECRET}"

SECRET_JSON='{ "password": "hello" }'

for key in \
  ${WORKER_CLASS}:h \
  ${WORKER_CLASS}:start:q \
  ${WORKER_CLASS}:started:q \
  ${WORKER_CLASS}:req:x \
  ${WORKER_CLASS}:res:x
do
  if redis-cli exists "${key}" | grep -q '^1$'
  then
    echo 🛑 redis-cli del "${key}"
    exit 1
  fi
done

hset() {
  redis-cli hset ${@} | grep -q '^1$'
}

hmset() {
  hset ${1} repo ${WORKER_REPO}
  hset ${1} class ${WORKER_CLASS}
  hset ${1} version ${WORKER_VERSION:=main}
  hset ${1} requestStream ${WORKER_CLASS}:req:x
  hset ${1} responseStream ${WORKER_CLASS}:res:x
  hset ${1} secretAlg aes256
}

hmset "${WORKER_CLASS}:h"
for workerId in 1
do
  hmset ${WORKER_CLASS}:${workerId}:h
  hset ${WORKER_CLASS}:${workerId}:h consumerId ${workerId}
  hset ${WORKER_CLASS}:${workerId}:h requestLimit 1
  redis-cli lpush ${WORKER_CLASS}:start:q ${workerId} | grep -q '^[1-9]$'
  echo "${SECRET_JSON}" | 
    openssl enc -aes256 -k ${INPUT_SECRET} -base64 | 
    redis-cli -x hset ${WORKER_CLASS}:${workerId}:h encrypted | grep -q '^1$'
  redis-cli hset ${WORKER_CLASS}:${workerId}:h encryptedType 'v1:aes256'
  redis-cli hget ${WORKER_CLASS}:${workerId}:h encrypted | 
    openssl enc -d -aes256 -base64 -k ${INPUT_SECRET}
done

redis-cli xgroup create "${WORKER_CLASS}:req:x" 'worker' '$' mkstream | grep -q '^OK$'

hset ${WORKER_CLASS}:1:h denoOptions "--inspect=127.0.0.1:9228"

echo ${INPUT_SECRET} | exec ./bootstrap.sh "${WORKER_CLASS}"
