import { connect } from "https://deno.land/x/redis/mod.ts";
import { decryptJson, unflattenRedis } from "../utils.ts";
import * as log from "https://deno.land/std@0.106.0/log/mod.ts";

const redis = await connect({
  hostname: "127.0.0.1",
  port: 6379,
});

if (Deno.args.length !== 1) {
  throw new Error("Missing config key");
}

const workerKey = Deno.args[0];

if (!/:h$/.test(workerKey)) {
  throw new Error(
    `Expecting worker key argument with ':h' postfix: ${workerKey}`,
  );
}

const configMap = unflattenRedis(await redis.hgetall(workerKey));
const config = {
  workerType: "demo-worker",
  requestStream: configMap.get("requestStream") as string,
  responseStream: configMap.get("responseStream") as string,
  consumerId: configMap.get("consumerId") as string,
  requestLimit: parseInt(configMap.get("requestLimit") as string || "0"),
  encryptedIv: configMap.get("encryptedIv") as string,
  encryptedAlg: configMap.get("encryptedAlg") as string,
  encryptedJson: configMap.get("encryptedJson") as string,
  xreadGroupBlockMillis: 2000,
  replyExpireSeconds: 8,
};

const secretConfig = await decryptJson(
  config.encryptedIv,
  config.encryptedJson,
);
if (secretConfig.type !== config.workerType) {
  throw new Error(
    `Expecting encryptedJson to have type ${config.workerType}: ${secretConfig.type}`,
  );
}

if (await redis.hexists(workerKey, "pid") === 1) {
  throw new Error(
    `Expecting instance hashes to have empty 'pid' field: ${workerKey}`,
  );
}

await redis.hset(workerKey, ["pid", Deno.pid]);

let requestCount = 0;

log.info(`Started with secret config type: ${secretConfig.type}`);

while (config.requestLimit === 0 || requestCount < config.requestLimit) {
  if ((await redis.hget(workerKey, "pid")) !== String(Deno.pid)) {
    throw new Error("Aborting because 'pid' field removed/changed");
  }

  const [reply] = await redis.xreadgroup(
    [[config.requestStream, ">"]],
    {
      group: "worker",
      consumer: config.consumerId,
      block: config.xreadGroupBlockMillis,
      count: 1,
    },
  );

  if (!reply || reply.messages.length === 0) {
    continue;
  }

  requestCount++;
  const received = Date.now();

  if (reply.messages.length !== 1) {
    throw new Error(
      `messagesLength: Expecting 1 message: ${reply.messages.length}`,
    );
  }

  const { xid, fieldValues } = reply.messages[0];
  const { ref, type, ...payload } = fieldValues;
  if (!ref) {
    throw new Error(`requestRef: Expecting ref property in request`);
  }
  const res = {
    ref,
    source: config.workerType,
  };
  if (type !== config.workerType) {
    throw new Error(
      `requestType: Request type '${type}' does not match worker type '${config.workerType}`,
    );
  }
  try {
    Object.assign(res, await handleRequest(payload), { code: 200 });
  } catch (err) {
    Object.assign(res, { code: 500, err: { message: err.message }, payload });
  }

  const tx = redis.tx();
  tx.lpush(
    `res:${ref}`,
    JSON.stringify(
      Object.assign(res, { time: new Date().toISOString() }, res),
    ),
  );
  tx.expire(`res:${ref}`, config.replyExpireSeconds);
  tx.xadd(config.responseStream, "*", {
    ref,
    type: config.workerType,
    xid: [xid.unixMs, xid.seqNo].join("-"),
    res: JSON.stringify(res),
  });
  tx.hmset(`req:${ref}:h`, {
    demoWorkerTrace: JSON.stringify({
      received,
      completed: Date.now(),
      res: JSON.stringify(res),
    }),
  });
  await tx.flush();
  log.info(`Processed ref: ${ref}`);
}

Deno.exit(0);

async function handleRequest(payload: object) {
  const response = {
    type: "demo-worker-res",
    worker: {
      workerType: config.workerType,
      workerKey,
    },
    request: {
      payload,
    },
  };
  return response;
}
