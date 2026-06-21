import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const srcContractsDir = path.join(__dirname, "contracts", "artifacts", "contracts");
const destDir = path.join(__dirname, "frontend", "src", "contracts");

fs.mkdirSync(destDir, { recursive: true });

// Copy ABIs
const contracts = ["Escrow", "ReputationRegistry"];
const abis = {};

for (const name of contracts) {
  const file = path.join(srcContractsDir, `${name}.sol`, `${name}.json`);
  const artifact = JSON.parse(fs.readFileSync(file, "utf8"));
  abis[name] = artifact.abi;
}

// Copy deployments
const deploymentsFile = path.join(__dirname, "deployments", "nexus_mainnet.json");
const deployments = JSON.parse(fs.readFileSync(deploymentsFile, "utf8"));

const output = {
  abis,
  addresses: {
    Escrow: deployments.contracts.Escrow.address,
    ReputationRegistry: deployments.contracts.ReputationRegistry.address,
  },
  chainId: deployments.chainId,
};

fs.writeFileSync(
  path.join(destDir, "index.ts"),
  `export const contracts = ${JSON.stringify(output, null, 2)};\n`
);

console.log("Artifacts copied to frontend (Mainnet).");
