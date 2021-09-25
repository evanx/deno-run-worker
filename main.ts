import * as Colors from "https://deno.land/std/fmt/colors.ts";
import * as log from "https://deno.land/std@0.106.0/log/mod.ts";
import { connect } from "https://deno.land/x/redis/mod.ts";
import { unflattenRedis } from "./utils.ts";

const redis = await connect({
  hostname: "127.0.0.1",
  port: 6379,
});

export interface RunOpts {
  allowNet: string | boolean | undefined;
}

if (Deno.args.length !== 4) {
  log.error("Usage: <repo> <class> <version> <id>");
  Deno.exit(9);
}

const workerRepo = Deno.args[0];
const workerClass = Deno.args[1];
const workerVersion = Deno.args[2];
const workerId = Deno.args[3];
if (!/^[a-z][-a-z0-9_]*$/.test(workerClass)) {
  log.error(`Invalid worker class: ${workerClass}`);
  Deno.exit(9);
}
if (!/^[a-z0-9][-a-z0-9_]*$/.test(workerId)) {
  log.error(`Invalid worker ID: ${workerId}`);
  Deno.exit(9);
}
const workerUrl =
  (workerVersion === "local"
    ? [workerRepo, workerClass, "worker.ts"]
    : [workerRepo, workerClass, workerVersion, "worker.ts"]).join(
      "/",
    );
const workerKey = `${workerClass}:${workerId}:h`;
const workerMap = unflattenRedis(await redis.hgetall(workerKey));
log.info(
  `deno run ${Colors.cyan(workerUrl)} ${Colors.blue(workerKey)}`,
);
log.info({ workerMap });

const allowOptions = ["--allow-net=127.0.0.1:6379"];
const denoOptions = (workerMap.get("denoOptions") || "").split(" ");
const options = [...allowOptions, ...denoOptions];
const cmd = [
  "deno",
  "run",
  ...options,
  workerUrl,
  workerKey,
];
log.info({ cmd });
const p = Deno.run({ cmd });
const { code } = await p.status();
p.close();
Deno.exit(code);
