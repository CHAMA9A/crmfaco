import { describe, expect, test } from "bun:test";

import { calculateInvoiceTotals, formatMad, sumMoney } from "./money";

describe("invoice money", () => {
  test("formats SOMA totals in MAD", () => {
    expect(formatMad("10500.00")).toBe("10 500,00 MAD");
  });

  test("adds decimal strings without floating point drift", () => {
    expect(sumMoney(["0.10", "0.20", "10499.70"])).toBe("10500.00");
  });

  test("calculates HT, 20% tax and TTC using exact minor units", () => {
    expect(calculateInvoiceTotals(["6500.00", "4000.00"])).toEqual({
      totalHt: "10500.00",
      tax: "2100.00",
      totalTtc: "12600.00",
    });
  });

  test("rounds tax to the nearest cent", () => {
    expect(calculateInvoiceTotals(["0.03"])).toEqual({
      totalHt: "0.03",
      tax: "0.01",
      totalTtc: "0.04",
    });
  });
});
