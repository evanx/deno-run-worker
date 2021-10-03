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

if (Deno.args.length !== 2) {
  log.error("Usage: <url> <key>");
  Deno.exit(9);
}

const workerUrl = Deno.args[0];
const workerKey = Deno.args[1];

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
