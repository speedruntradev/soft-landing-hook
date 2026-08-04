import fs from "node:fs";
import { execFileSync } from "node:child_process";

const [buildInfoPath, solcPath] = process.argv.slice(2);
if (!buildInfoPath || !solcPath) {
  throw new Error("usage: node script/normalize-build-info.mjs <build-info.json> <solc-binary>");
}

const buildInfo = JSON.parse(fs.readFileSync(buildInfoPath, "utf8"));
const versionOutput = execFileSync(solcPath, ["--version"], { encoding: "utf8" });
const match = versionOutput.match(/Version:\s+(\d+\.\d+\.\d+\+commit\.[0-9a-f]{8})/u);
if (!match) throw new Error("could not derive the canonical compiler identity from solc --version");

const canonicalVersion = match[1];
const shortVersion = canonicalVersion.split("+")[0];
if (buildInfo.solcVersion !== shortVersion) throw new Error("build-info short compiler version differs from solc");
if (![shortVersion, canonicalVersion].includes(buildInfo.solcLongVersion)) {
  throw new Error("build-info long compiler version is neither short nor canonical");
}

// Foundry 1.7.1 records only the short version when --use receives a local compiler path.
// The exact binary is independently queried above before filling the canonical envelope field.
buildInfo.solcLongVersion = canonicalVersion;
fs.writeFileSync(buildInfoPath, `${JSON.stringify(buildInfo)}\n`);
console.log(JSON.stringify({ buildInfoPath, solcLongVersion: canonicalVersion }));
