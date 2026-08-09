export function shortenAddress(address: string, chars = 4): string {
  if (address.length < 2 + chars * 2) return address;
  return `${address.slice(0, chars + 2)}…${address.slice(-chars)}`;
}

export function formatTokenAmount(amount: bigint, decimals: number): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;
  if (fraction === 0n) return whole.toString();

  const fractionStr = fraction.toString().padStart(decimals, "0").replace(/0+$/, "");
  return `${whole}.${fractionStr}`;
}

export function parseTokenAmount(value: string, decimals: number): bigint {
  const trimmed = value.trim();
  if (!trimmed) return 0n;
  const [wholePart, fractionPart = ""] = trimmed.split(".");
  const paddedFraction = fractionPart.slice(0, decimals).padEnd(decimals, "0");
  const whole = wholePart ? BigInt(wholePart) : 0n;
  const fraction = paddedFraction ? BigInt(paddedFraction) : 0n;
  return whole * 10n ** BigInt(decimals) + fraction;
}

export function formatDate(unixSeconds: number): string {
  if (!unixSeconds) return "—";
  return new Date(unixSeconds * 1000).toLocaleString();
}
