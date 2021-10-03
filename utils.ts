import { Aes } from "https://deno.land/x/crypto/aes.ts";
import { Cbc, Padding } from "https://deno.land/x/crypto/block-modes.ts";
import { decode as decodeHex } from "https://deno.land/std/encoding/hex.ts";
import { decode as decodeBase64 } from "https://deno.land/std/encoding/base64.ts";

export function unflattenRedis(array: string[]): Map<String, String> {
  const map = new Map();
  for (let index = 0; index < array.length; index += 2) {
    map.set(array[index], array[index + 1]);
  }
  return map;
}

export function parseRedisVersion(text: string) {
  const match = text.match(/\bredis_version:(\d\.\d+)/);
  return match ? match.pop() : "5.0";
}

export async function readStream(
  stream: Deno.Reader,
  limit: number,
): Promise<string> {
  const buffer = new Uint8Array(limit);
  const length = <number> await stream.read(buffer);
  return new TextDecoder().decode(buffer.subarray(0, length))
    .trim();
}

export async function decryptJson(
  ivHex: string, // openssl enc takes hex args for AES iv and password
  encryptedBase64: string, // openssl enc can produce base64 output
  inputStream = Deno.stdin,
) {
  const te = new TextEncoder();
  const td = new TextDecoder();
  const [type, input] = (await readStream(inputStream, 256)).split(" ");
  if (type !== "worker-v0") {
    throw new Error(`Invalid input type: ${type}`);
  }
  const secret = decodeHex(te.encode(input));
  const iv = decodeHex(te.encode(ivHex));
  const decipher = new Cbc(Aes, secret, iv, Padding.PKCS7);
  const decrypted = decipher.decrypt(decodeBase64(encryptedBase64));
  return JSON.parse(td.decode(decrypted));
}
