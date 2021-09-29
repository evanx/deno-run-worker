#!/bin/bash
set -eu

INPUT_SECRET=`openssl rand 16 -hex`
INPUT_IV=`openssl rand 16 -hex`
SECRET_JSON=`
  echo -n '{ "password": "hello", "type": "demo-config" }' |
  openssl base64
`
encrypted=`
  echo ${INPUT_SECRET} ${INPUT_IV} ${SECRET_JSON} | 
    deno run test/encrypt.ts
`

echo "Repo ${WORKER_REPO:=https://raw.githubusercontent.com/evanx}"
echo "Class ${WORKER_CLASS:=deno-date-iso}"

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
  hset ${1} encryptedAlg aes-128-cbc
  hset ${1} encryptedIv ${INPUT_IV}
  hset ${1} encrypted ${encrypted}
}

hmset "${WORKER_CLASS}:h"
for workerId in 1
do
  hmset ${WORKER_CLASS}:${workerId}:h
  hset ${WORKER_CLASS}:${workerId}:h consumerId ${workerId}
  hset ${WORKER_CLASS}:${workerId}:h requestLimit 10
  redis-cli lpush ${WORKER_CLASS}:start:q ${workerId} | grep -q '^[1-9]$'
done

redis-cli xgroup create "${WORKER_CLASS}:req:x" 'worker' '$' mkstream | grep -q '^OK$'

hset ${WORKER_CLASS}:1:h denoOptions ${WORKER_DENO_OPTIONS:=--inspect=127.0.0.1:9228}

echo workerAES-v0 ${INPUT_SECRET} | exec ./bootstrap.sh "${WORKER_CLASS}"
