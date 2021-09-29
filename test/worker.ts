import { connect } from "https://deno.land/x/redis/mod.ts";
import { decryptJson, unflattenRedis } from "../utils.ts";

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
  workerUrl: "https://raw.githubusercontent.com/evanx/deno-date-iso/",
  requestStream: configMap.get("requestStream") as string,
  responseStream: configMap.get("responseStream") as string,
  consumerId: configMap.get("consumerId") as string,
  requestLimit: parseInt(configMap.get("requestLimit") as string || "0"),
  encryptedIv: configMap.get("encryptedIv") as string,
  encryptedAlg: configMap.get("encryptedAlg") as string,
  encrypted: configMap.get("encrypted") as string,
  xreadGroupBlockMillis: 2000,
  replyExpireSeconds: 8,
};

const secretConfig = await decryptJson(config.encryptedIv, config.encrypted);

if (await redis.hexists(workerKey, "pid") === 1) {
  throw new Error(
    `Expecting instance hashes to have empty 'pid' field: ${workerKey}`,
  );
}

await redis.hset(workerKey, ["pid", Deno.pid]);

let requestCount = 0;

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

  if (reply.messages.length !== 1) {
    throw new Error(`Expecting 1 message: ${reply.messages.length}`);
  }

  const { xid, fieldValues } = reply.messages[0];
  const { ref, workerUrl } = fieldValues;
  let code;
  let res;
  if (!ref) {
    await redis.hincrby(workerKey, "err:ref", 1);
    continue;
  } else if (!workerUrl.startsWith(config.workerUrl)) {
    await redis.hincrby(workerKey, "err:workerUrl", 1);
    code = 400;
    res = { err: "workerUrl", workerUrl, allowPrefix: config.workerUrl };
  } else {
    code = 200;
    res = { data: new Date().toISOString() };
  }
  const tx = redis.tx();
  tx.lpush(
    `res:${ref}`,
    JSON.stringify(Object.assign({ code }, res)),
  );
  tx.expire(`res:${ref}`, config.replyExpireSeconds);
  tx.xadd(config.responseStream, "*", {
    ref,
    xid: [xid.unixMs, xid.seqNo].join("-"),
    workerUrl,
    code,
  });
  await tx.flush();
  console.log(`Processed: ${ref}`, res);
}

Deno.exit(0);
