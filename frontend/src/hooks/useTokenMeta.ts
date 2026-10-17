"use client";

import { useReadContracts } from "wagmi";
import type { Address } from "viem";
import { erc20Abi } from "@/lib/erc20Abi";
import { NATIVE_TOKEN } from "@/lib/contract";
import { selectedChain, selectedChainId } from "@/lib/chain";

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
      { address: token, abi: erc20Abi, functionName: "symbol", chainId: selectedChainId },
      { address: token, abi: erc20Abi, functionName: "decimals", chainId: selectedChainId },
    ],
    query: { enabled: !isNative && !!token },
  });

  if (isNative) {
    return {
      symbol: selectedChain.nativeCurrency.symbol,
      decimals: selectedChain.nativeCurrency.decimals,
      isNative: true,
      isLoading: false,
    };
  }

  return {
    symbol: (data?.[0]?.result as string) ?? "TOKEN",
    decimals: (data?.[1]?.result as number) ?? 18,
    isNative: false,
    isLoading,
  };
}
