"use client";

import { useReadContracts } from "wagmi";
import type { Address } from "viem";
import { erc20Abi } from "@/lib/erc20Abi";
import { NATIVE_TOKEN } from "@/lib/contract";
import { nexusL1 } from "@/lib/chain";

export interface TokenMeta {
  symbol: string;
  decimals: number;
  isNative: boolean;
  isLoading: boolean;
}

export function useTokenMeta(token: Address | undefined): TokenMeta {
  const isNative = !token || token.toLowerCase() === NATIVE_TOKEN;

  const { data, isLoading } = useReadContracts({
    contracts: [
      { address: token, abi: erc20Abi, functionName: "symbol" },
      { address: token, abi: erc20Abi, functionName: "decimals" },
    ],
    query: { enabled: !isNative && !!token },
  });

  if (isNative) {
    return { symbol: nexusL1.nativeCurrency.symbol, decimals: 18, isNative: true, isLoading: false };
  }

  return {
    symbol: (data?.[0]?.result as string) ?? "TOKEN",
    decimals: (data?.[1]?.result as number) ?? 18,
    isNative: false,
    isLoading,
  };
}
