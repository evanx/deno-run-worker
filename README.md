# deno-run-worker

This repo includes scripts to run Deno "workers" e.g. to collectively consume an event stream.

## Goals

We wish to optimise an archetype of Redis-driven microservices:

- the development of services on ones own laptop must be "fun and fast"
- no-code automated testing to ensure quality
- deployments, upgrades and debugging must be relatively pain-free

### Achitecture

We've chosen to explore Redis-driven microservices in Deno, with side-effects restricted to Redis only.

- JavaScript/TypeScript: popular and familiar
- Deno: secure by default
- Redis: maps well to programming data structures

We will also explore services that integrate Redis to PostgreSQL such that PostgreSQL can be used for bulk long-term persistence, e.g. https://github.com/evanx/lula-sync.

### Application

We will trial this approach for the development of chat bots. Such applications have the advantage of not requiring front-end infrastructure or coding. The messaging platform provider e.g. Telegram.org,
offers their own mobile and web clients, with user authentication. This de-scopes everything except the custom back-end services that comprise a chat bot.

We believe a "fun and fast" Deno/Redis backend platform should combine well this application space. A hobbyist chat bot does not require much storage for starters. Redis is great as a simple data store.

#### Scaling

We are interested in scale too. Therefore we wish to provide Redis/PostgreSQL "adapter services" that enable bulk storage, secondary indexes, SQL queries, text search and JSON queries.

We envisage that an application deployment can include adapters from trusted sources, as an extension of the underlying platform, that promotes our "fun and fast" primary goal at scale.

#### Re-scaling

As a stretch goal, we wish to introduce tooling that enables the development of a suite of application services such that:

- services can invoke each other directly as in a monolith
- services can later be independently deployed and scaled

The idea fermenting is:

- if our service's connection to Redis is considered critical
- since we intend to provide tooling for no-code automated integration tests against a JSON spec
- where presumably that spec defines the service interfaces
- then surely we could automatically marshall requests and responses via Redis
- where the failure of any Redis command would already be considered a fatal error
- therefore we are mitigating the "fallacy of distributing computing" that the network is reliable

## Demo

```shell
demo/clean.sh && demo/run.sh
```

The `demo/run.sh` shell script will start a demo worker: https://github.com/evanx/deno-run-worker/blob/main/demo/worker.ts

This script will setup the keys in Redis for this worker, e.g. `demo-worker:1:h` for worker ID `1.`

```
$ redish demo-worker:1:h
type demo-worker
url https://raw.githubusercontent.com/evanx/deno-run-worker/main/demo/worker.ts
version main
requestStream demo-worker:req:x
responseStream demo-worker:res:x
consumerId 1
requestLimit 1
denoOptions --inspect=127.0.0.1:9229
```

Note that a worker `version` of `local` is used for local development, where the `workerUrl` is a local folder in this case, rather than a Github URL for example.

This `demo.sh` script will invoke `bootstrap.sh` as follows:

```
    deno run --allow-net=127.0.0.1:6379 --allow-run ./main.ts \
      ${WORKER_URL} ${workerId} ||
```

Our Deno runner must create the correct options e.g. `--allow-net` as required by our worker:

```
const cmd = [
  "deno",
  "run",
  ...options,
  workerUrl,
  workerKey,
];`
```

Our worker takes a Redis hashes key `workerKey` as its sole CLI parameter. It will configure itself via these Redis hashes. The `workerKey` is built as follows:

```
const workerKey = `${workerType}:${workerId}:h`;
```

We setup Deno options with `--inspect` and can attach a debugger as seen below:

![image](https://user-images.githubusercontent.com/899558/134762517-4ccc28b3-6f8e-4ab9-8529-49054eb7f1ee.png)

## Redis-driven worker concept

See example worker: https://github.com/evanx/deno-run-worker/blob/main/demo/worker.ts

This `worker.ts` script is a Redis-driven microservice as follows:

- the microservice requires a Redis hashes "worker key" as a CLI parameter
- these worker hashes provide configuration e.g. the `requestStream` Redis key
- an AES key is provided by `stdin` to decrypt any sensitive credentials in an `encryptedJson` field
- the worker sets and monitors the `pid` field to control its lifecycle
- the worker will `xreadgroup` using the `worker` consumer group to process requests
- the worker will push the response to a single-entry "list" which will expire after a few seconds

The intention is that other workers in the system can `xadd` requests, and `brpop` responses with a timeout.

### Worker lifecycle controlled via Redis

Each worker monitors its `pid` field of its hashes, and must exit if this field changes:

```typscript
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

  ... // process reply
}

Deno.exit(0);
```

### Request processing from Redis stream

We process the Redis `reply` as follows:

```typescript
if (!reply || reply.messages.length === 0) {
  continue;
}

requestCount++;

if (reply.messages.length !== 1) {
  throw new Error(`Expecting 1 message: ${reply.messages.length}`);
}

const message = reply.messages[0];
const { ref, workerUrl, ...request } = message.fieldValues;
```

We process the `request` and push the `response` with matching `ref` as follows:

```typescript
const tx = redis.tx();
tx.lpush(`res:${ref}`, JSON.stringify(Object.assign({ code }, res)));
tx.expire(`res:${ref}`, config.replyExpireSeconds);
await tx.flush();
```

Additionally, we record the response in a response stream

```typescript
tx.xadd(
  config.responseStream,
  '*',
  {
    ref,
    xid: [xid.unixMs, xid.seqNo].join('-'),
    workerUrl,
    code,
  },
  { elements: config.responseStreamLimit }
);
```

where we might limit the response stream to a few elements only, for testing and debugging purposes.

### Config from Redis hashes

Our worker will read its config from its Redis `workerKey` as follows:

```typescript
const configMap = unflattenRedis(await redis.hgetall(workerKey));
const config = {
  workerType: 'demo-worker',
  requestStream: configMap.get('requestStream') as string,
  responseStream: configMap.get('responseStream') as string,
  consumerId: configMap.get('consumerId') as string,
  requestLimit: parseInt((configMap.get('requestLimit') as string) || '0'),
  encryptedIv: configMap.get('encryptedIv') as string,
  encryptedAlg: configMap.get('encryptedAlg') as string,
  encryptedJson: configMap.get('encryptedJson') as string,
  xreadGroupBlockMillis: 2000,
  replyExpireSeconds: 8,
};
```

### Secrets encrypted at rest in Redis

The following util function is used to read an AES key from the `stdin` and use this to decrypt a JSON string e.g. containing sensitive credentials stored in Redis:

```typescript
export async function decryptJson(
  ivHex: string, // openssl enc takes hex args for AES iv and password
  encryptedBase64: string, // openssl enc can produce base64 output
  inputStream = Deno.stdin
) {
  const te = new TextEncoder();
  const td = new TextDecoder();
  const [type, input] = (await readStream(inputStream, 256)).split(' ');
  if (type !== 'worker-v0') {
    throw new Error(`Invalid input type: ${type}`);
  }
  const secret = decodeHex(te.encode(input));
  const iv = decodeHex(te.encode(ivHex));
  const decipher = new Cbc(Aes, secret, iv, Padding.PKCS7);
  const decrypted = decipher.decrypt(decodeBase64(encryptedBase64));
  return JSON.parse(td.decode(decrypted));
}
```

Then in our worker, we can extract the `encryptedJson` JSON config simply as follows:

```typescript
const secretConfig = await decryptJson(
  config.encryptedIv,
  config.encryptedJson
);
```

### Utils

### Request tracing

Each request can be tracked via its own hashes key e.g. `req:1:h` as seen the in screenshot below.

Services can attach any related data to the request hashes e.g. progress or debugging data.

Clearly each request that is created by the system must have a unique ID across the various related services that might operate on this request, to avoid any clashes.

<hr>
