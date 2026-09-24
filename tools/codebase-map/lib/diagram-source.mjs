import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

export const diagramPath = "docs/architecture/intentive-codeflow.mmd";
const repository = "https://github.com/sruj75/knowledge-athlete";

/** Load only the canonical diagram; no runtime fetch or second maintained copy. */
export function loadDiagram({
  appDirectory = process.cwd(),
  environment = process.env,
  git = (args, cwd) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(),
} = {}) {
  const root = path.resolve(appDirectory, "../..");
  const source = readFileSync(path.join(root, diagramPath), "utf8");
  if (!source.trim()) throw new Error(`The canonical diagram is empty: ${diagramPath}`);
  if (source.length > 200_000) throw new Error("The diagram exceeds the viewer's 200,000-character limit.");

  let commit = environment.VERCEL_GIT_COMMIT_SHA || environment.GITHUB_SHA || null;
  if (commit && !/^[0-9a-f]{40}$/i.test(commit)) throw new Error("The build commit must be a full Git SHA.");
  if (!commit) {
    try {
      // An edited local checkout must not claim to display an immutable commit.
      if (!git(["status", "--porcelain", "--untracked-files=normal"], root)) {
        commit = git(["rev-parse", "HEAD"], root);
      }
    } catch {
      // Local source archives can still be viewed without Git metadata.
    }
  }
  if (environment.VERCEL && !commit) throw new Error("Vercel builds require VERCEL_GIT_COMMIT_SHA.");
  return {
    source,
    commit,
    sourceUrl: commit ? `${repository}/blob/${commit}/${diagramPath}` : null,
  };
}
