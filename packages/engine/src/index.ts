/**
 * Package identity for the co-evolve engine. Placeholder scaffold (WP-03) --
 * real engine primitives land in Phase 1 (adapters, bounce loop, contracts).
 */
export interface EngineInfo {
  readonly name: string;
  readonly version: string;
}

export const engineInfo: EngineInfo = {
  name: "@alanshurafa/co-evolve",
  version: "0.0.0-dev",
};

export * from "./state/index.js";

export * from "./adapters/index.js";

export { runWithDeadline, type RunResult, type RunWithDeadlineOptions, type RunOutcome } from "./proc/deadline.js";
