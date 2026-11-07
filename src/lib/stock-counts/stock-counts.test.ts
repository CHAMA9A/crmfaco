import { describe, expect, test } from "bun:test";

import { buildStockEvidencePath, signedDifference } from "./types";

describe("stock count presentation helpers", () => {
  test("formats signed differences without hiding shortages", () => {
    expect(signedDifference(5)).toBe("+5");
    expect(signedDifference(-20)).toBe("-20");
    expect(signedDifference(0)).toBe("0");
  });

  test("builds actor-scoped private evidence paths", () => {
    expect(
      buildStockEvidencePath(
        "11111111-1111-4111-8111-111111111111",
        "counts",
        "22222222-2222-4222-8222-222222222222",
        "photo inventaire 5L.png",
        "token",
      ),
    ).toBe(
      "11111111-1111-4111-8111-111111111111/counts/22222222-2222-4222-8222-222222222222/token-photo-inventaire-5L.png",
    );
  });
});
