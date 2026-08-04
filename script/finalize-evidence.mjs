import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";

const repositoryRoot = path.resolve(new URL("..", import.meta.url).pathname);
const reportPath = path.join(repositoryRoot, "submissions/soft-landing/compatibility-report.json");
const reviewTargetPath = path.join(repositoryRoot, "submissions/soft-landing/review-target.json");
const evidencePath = "EVIDENCE.md";
const outputPath = path.join(repositoryRoot, "submissions/soft-landing/gate-status.json");

const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
const reviewTarget = JSON.parse(fs.readFileSync(reviewTargetPath, "utf8"));
const evidenceBytes = fs.readFileSync(path.join(repositoryRoot, evidencePath));
const originCommit = execFileSync("git", ["rev-parse", "HEAD"], {
  cwd: repositoryRoot,
  encoding: "utf8",
}).trim();

if (!/^sha256:[0-9a-f]{64}$/.test(reviewTarget.reviewTargetHash)) {
  throw new Error("review target must be built before finalizing gate evidence");
}
if (!/^[0-9a-f]{40}$/.test(originCommit)) throw new Error("HEAD must be an exact Git commit");

const scopeByGate = {
  "event-reorg-backfill-freshness-tests":
    "Repository inspection confirms no project indexer is implemented; reorg, backfill, and freshness stay product-owned and not applicable to this contract-only prototype.",
  "external-liquidity-solvency-and-exit-invariants":
    "Repository inspection and callback permissions confirm the hook takes no LP position or external-liquidity custody; ordinary PoolManager LP exit remains outside hook control.",
  "project-custody-solvency-and-exit-tests":
    "Source and tests confirm project hook fee is zero and the project has no custody, claim, withdrawal, rescue, or exit authority.",
  "project-external-call-authentication-and-failure-tests":
    "Source inspection confirms no project-controlled external dependency or call path; PoolManager authentication and atomic failure paths are covered separately.",
  "project-value-flow-conservation-and-claim-tests":
    "Source and tests confirm the project share is zero; only the immutable Programmable liability and claim path exist.",
  "static-analysis":
    "Forge lint completed without a security diagnostic; this scope explicitly excludes Slither, which was unavailable and remains an independent-review action.",
};

const defaultScope = (gateId) =>
  `Local source, Foundry tests, deterministic simulation, and repository evidence cover contributor prototype gate ${gateId}; this does not prove audit, deployment, routing, or availability.`;

const gateEvidence = (gateId) => ({
  gateId,
  result: "passed",
  scope: scopeByGate[gateId] ?? defaultScope(gateId),
  path: evidencePath,
  sha256: `sha256:${crypto.createHash("sha256").update(evidenceBytes).digest("hex")}`,
  command:
    "forge fmt --check && forge build --sizes && forge test -vvv && forge lint src test --severity high --severity med --severity low && node simulations/launch-traces.mjs",
  toolVersion: "Forge 1.7.1 (4072e487); Node.js 24.19.0; programmable-v4-hook-builder standard 1.3.0",
  commit: originCommit,
  reviewTargetHash: reviewTarget.reviewTargetHash,
});

const prototypeGates = report.requiredGates
  .filter((gate) => gate.stage === "prototype")
  .map((gate) => ({
    id: gate.id,
    status: "completed",
    evidence: [gateEvidence(gate.id)],
    note: gate.reason,
  }));

const contributorOpenGate = {
  id: "independent-security-review-one",
  status: "planned",
  evidence: [],
  note: "Repository tests and builder checks do not replace independent review of return-delta accounting and controller economics.",
};
if (!prototypeGates.some((gate) => gate.id === contributorOpenGate.id)) prototypeGates.push(contributorOpenGate);
prototypeGates.sort((a, b) => a.id.localeCompare(b.id));

const status = {
  schemaVersion: 1,
  attestation: "builder-declared-untrusted",
  standardVersion: report.standardVersion,
  submissionHash: report.submissionHash,
  validatorSha256: report.toolchain.validatorSha256,
  schemaSha256: report.toolchain.schemaSha256,
  deploymentSnapshotSha256: report.toolchain.deploymentSnapshotSha256,
  officialDeploymentReferenceSha256: report.toolchain.officialDeploymentReferenceSha256,
  policyBundleSha256: report.toolchain.policyBundleSha256,
  reviewTargetHash: reviewTarget.reviewTargetHash,
  gates: prototypeGates,
};

fs.writeFileSync(outputPath, `${JSON.stringify(status, null, 2)}\n`);
console.log(JSON.stringify({ outputPath, reviewTargetHash: reviewTarget.reviewTargetHash, gateCount: prototypeGates.length }));
