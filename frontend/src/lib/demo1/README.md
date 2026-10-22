# Demo 1 signing helpers

`intent.ts` is the canonical TypeScript representation of the Demo 1 `NexEscrowCore` EIP-712 signing surface.

The helpers in this directory are deterministic encoding utilities only. They do not submit transactions, select networks, enable BOT mainnet 677, or establish deployment/production evidence.

`intent-vectors.json` is a fixed regression vector shared conceptually with the Solidity interoperability test. Any intentional change to the signed schema or ABI commitments must update both sides in the same review.
