// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Minimal EIP-1271 smart-account wallet: validates an owner's ECDSA signature
///         over the hash and returns the magic value only when it recovers the owner.
contract MockERC1271Wallet {
    bytes4 internal constant MAGIC = 0x1626ba7e; // IERC1271.isValidSignature.selector

    address public owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == owner) {
            return MAGIC;
        }
        return 0xffffffff;
    }
}

/// @notice An EIP-1271 wallet that rejects everything — used to prove fail-closed
///         behaviour: no signature of any shape is ever accepted.
contract MockRejectingWallet {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }
}
