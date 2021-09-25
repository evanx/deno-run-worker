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
