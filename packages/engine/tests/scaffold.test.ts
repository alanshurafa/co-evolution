import { describe, expect, it } from "vitest";
import { engineInfo } from "../src/index.js";

describe("engine scaffold", () => {
  it("exposes typed package identity", () => {
    expect(engineInfo.name).toBe("@alanshurafa/co-evolve");
    expect(engineInfo.version).toBe("0.0.0-dev");
  });
});
