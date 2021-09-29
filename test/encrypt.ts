import { readStream } from "../utils.ts";
import { Aes } from "https://deno.land/x/crypto/aes.ts";
import { Cbc, Padding } from "https://deno.land/x/crypto/block-modes.ts";
import { decode as decodeHex } from "https://deno.land/std/encoding/hex.ts";
import { decode as decodeBase64 } from "https://deno.land/std/encoding/base64.ts";
import { encode as encodeBase64 } from "https://deno.land/std/encoding/base64.ts";

const te = new TextEncoder();
const td = new TextDecoder();

const [secretHex, ivHex, plainBase64] = (await readStream(Deno.stdin, 256))
  .split(" ");
const secret = decodeHex(te.encode(secretHex));
const iv = decodeHex(te.encode(ivHex));
const plain = decodeBase64(plainBase64);
const cipher = new Cbc(Aes, secret, iv, Padding.PKCS7);
const encrypted = cipher.encrypt(plain);

const decipher = new Cbc(Aes, secret, iv, Padding.PKCS7);
const decrypted = td.decode(decipher.decrypt(encrypted));
if (decrypted !== td.decode(plain)) {
  throw new Error("Decryption mismatch");
}

console.log(encodeBase64(encrypted));
