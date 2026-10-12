// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IResolver
/// @notice Boundary for a NexEscrow Demo 1 dispute-resolver module (whitepaper §5). The
///         settlement kernel uses a PUSH model: a resolver module is committed by address
///         in the agreement's `ResolutionPolicy` and delivers a final `buyerBps` by calling
///         the core's `rule` / `finalRule`. The core never calls back into the resolver, so
///         it stays a minimal kernel that does not care HOW a ruling was produced
///         (single key, Safe/multisig, M-of-N quorum, or an ERC-792 adapter). This
///         interface is the module-side convention for off-chain tooling to discover a
///         resolver's target core and kind.
interface IResolver {
    /// @return The NexEscrowCore this module is wired to submit rulings to.
    function core() external view returns (address);

    /// @return A short, human/tooling-readable label for the resolver kind.
    function resolverKind() external pure returns (string memory);
}
