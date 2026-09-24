import { describe, expect, test } from "bun:test";

import { formatMad, sumMoney } from "./money";

describe("invoice money", () => {
  test("formats SOMA totals in MAD", () => {
    expect(formatMad("10500.00")).toBe("10 500,00 MAD");
  });

  test("adds decimal strings without floating point drift", () => {
    expect(sumMoney(["0.10", "0.20", "10499.70"])).toBe("10500.00");
  });
});
