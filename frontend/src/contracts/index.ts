export const contracts = {
  "abis": {
    "Escrow": [
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "_reputationRegistry",
            "type": "address"
          }
        ],
        "stateMutability": "nonpayable",
        "type": "constructor"
      },
      {
        "inputs": [],
        "name": "InvalidAmount",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "InvalidDeadline",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "InvalidPayee",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "InvalidState",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "NoArbiter",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "ReentrancyGuardReentrantCall",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "Unauthorized",
        "type": "error"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "payer",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "payee",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "address",
            "name": "arbiter",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "deadline",
            "type": "uint256"
          }
        ],
        "name": "EscrowCreated",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "disputer",
            "type": "address"
          }
        ],
        "name": "EscrowDisputed",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "payer",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "amount",
            "type": "uint256"
          }
        ],
        "name": "EscrowFunded",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "payer",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "amount",
            "type": "uint256"
          }
        ],
        "name": "EscrowRefunded",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "payee",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "amount",
            "type": "uint256"
          }
        ],
        "name": "EscrowReleased",
        "type": "event"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "payee",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "arbiter",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "deadline",
            "type": "uint256"
          }
        ],
        "name": "createEscrow",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          }
        ],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          }
        ],
        "name": "dispute",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "name": "escrows",
        "outputs": [
          {
            "internalType": "address",
            "name": "payer",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "payee",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "arbiter",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "amount",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "deadline",
            "type": "uint256"
          },
          {
            "internalType": "enum Escrow.State",
            "name": "state",
            "type": "uint8"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          }
        ],
        "name": "fund",
        "outputs": [],
        "stateMutability": "payable",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "nextEscrowId",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          }
        ],
        "name": "refund",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "escrowId",
            "type": "uint256"
          }
        ],
        "name": "release",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "reputationRegistry",
        "outputs": [
          {
            "internalType": "contract ReputationRegistry",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      }
    ],
    "ReputationRegistry": [
      {
        "inputs": [],
        "stateMutability": "nonpayable",
        "type": "constructor"
      },
      {
        "inputs": [],
        "name": "EscrowAlreadySet",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "Unauthorized",
        "type": "error"
      },
      {
        "inputs": [],
        "name": "ZeroAddress",
        "type": "error"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "escrowContract",
            "type": "address"
          }
        ],
        "name": "EscrowContractSet",
        "type": "event"
      },
      {
        "anonymous": false,
        "inputs": [
          {
            "indexed": true,
            "internalType": "address",
            "name": "payer",
            "type": "address"
          },
          {
            "indexed": true,
            "internalType": "address",
            "name": "payee",
            "type": "address"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "amount",
            "type": "uint256"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "payerCount",
            "type": "uint256"
          },
          {
            "indexed": false,
            "internalType": "uint256",
            "name": "payeeCount",
            "type": "uint256"
          }
        ],
        "name": "SettlementRecorded",
        "type": "event"
      },
      {
        "inputs": [],
        "name": "escrowContract",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "offset",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "limit",
            "type": "uint256"
          }
        ],
        "name": "leaderboard",
        "outputs": [
          {
            "internalType": "address[]",
            "name": "addrs",
            "type": "address[]"
          },
          {
            "internalType": "uint256[]",
            "name": "counts",
            "type": "uint256[]"
          },
          {
            "internalType": "uint256[]",
            "name": "volumes",
            "type": "uint256[]"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "owner",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [],
        "name": "participantCount",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "uint256",
            "name": "",
            "type": "uint256"
          }
        ],
        "name": "participants",
        "outputs": [
          {
            "internalType": "address",
            "name": "",
            "type": "address"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "payer",
            "type": "address"
          },
          {
            "internalType": "address",
            "name": "payee",
            "type": "address"
          },
          {
            "internalType": "uint256",
            "name": "amount",
            "type": "uint256"
          }
        ],
        "name": "recordSettlement",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "user",
            "type": "address"
          }
        ],
        "name": "reputationOf",
        "outputs": [
          {
            "internalType": "uint256",
            "name": "count",
            "type": "uint256"
          },
          {
            "internalType": "uint256",
            "name": "volume",
            "type": "uint256"
          }
        ],
        "stateMutability": "view",
        "type": "function"
      },
      {
        "inputs": [
          {
            "internalType": "address",
            "name": "_escrowContract",
            "type": "address"
          }
        ],
        "name": "setEscrowContract",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
      }
    ]
  },
  "addresses": {
    "Escrow": "0x4B026F5475502507800ffC95B1bF464487C13dBe",
    "ReputationRegistry": "0x57832D20f406AE9d787EB46ABA214CF0D0aA2420"
  },
  "chainId": 3946
};
