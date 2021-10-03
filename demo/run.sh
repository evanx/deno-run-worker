#!/bin/bash
set -eu

INPUT_SECRET=`openssl rand 16 -hex` # openssl enc -k requires hex
INPUT_IV=`openssl rand 16 -hex` # openssl enc -iv requires hex
SECRET_JSON=`
  echo -n '{ "password": "hello", "type": "demo-worker" }' |
  openssl base64
`
encryptedJson=`
  echo ${INPUT_SECRET} ${INPUT_IV} ${SECRET_JSON} | 
    deno run demo/encrypt.ts
` # TODO: retry encrypt with openssl e.g. aes-128-cbc

echo "workerType ${WORKER_TYPE:=demo-worker}"
echo "workerUrl ${WORKER_URL:=https://raw.githubusercontent.com/evanx/deno-run-worker/main/demo/worker.ts}"

for key in \
  ${WORKER_TYPE}:h \
  ${WORKER_TYPE}:start:q \
  ${WORKER_TYPE}:started:q \
  ${WORKER_TYPE}:req:x \
  ${WORKER_TYPE}:res:x
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
  hset ${1} workerUrl ${WORKER_URL}
  hset ${1} workerType ${WORKER_TYPE}
  hset ${1} workerVersion ${WORKER_VERSION:=main}
  hset ${1} requestStream ${WORKER_TYPE}:req:x
  hset ${1} responseStream ${WORKER_TYPE}:res:x
  hset ${1} encryptedAlg aes-128-cbc
  hset ${1} encryptedIv ${INPUT_IV}
  hset ${1} encryptedJson ${encryptedJson}
}

hmset "${WORKER_TYPE}:h"
for workerId in 1
do
  hmset ${WORKER_TYPE}:${workerId}:h
  hset ${WORKER_TYPE}:${workerId}:h consumerId ${workerId}
  hset ${WORKER_TYPE}:${workerId}:h requestLimit 10
  redis-cli lpush ${WORKER_TYPE}:start:q ${workerId} | grep -q '^[1-9]$'
done

redis-cli xgroup create "${WORKER_TYPE}:req:x" 'worker' '$' mkstream | grep -q '^OK$'

hset ${WORKER_TYPE}:1:h denoOptions ${WORKER_DENO_OPTIONS:=--inspect=127.0.0.1:9228}

echo worker-v0 ${INPUT_SECRET} | exec ./bootstrap.sh "${WORKER_TYPE}"
