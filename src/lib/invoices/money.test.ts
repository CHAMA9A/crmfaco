import { describe, expect, test } from "bun:test";

import { calculateInvoiceTotals, formatMad, formatTaxRate, sumMoney } from "./money";

describe("invoice money", () => {
  test("formats SOMA totals in MAD", () => {
    expect(formatMad("10500.00")).toBe("10 500,00 MAD");
  });

  test("adds decimal strings without floating point drift", () => {
    expect(sumMoney(["0.10", "0.20", "10499.70"])).toBe("10500.00");
  });

  test("calculates HT, 20% tax and TTC using exact minor units", () => {
    expect(calculateInvoiceTotals(["6500.00", "4000.00"], "20.00")).toEqual({
      totalHt: "10500.00",
      tax: "2100.00",
      totalTtc: "12600.00",
    });
  });

  test("rounds tax to the nearest cent", () => {
    expect(calculateInvoiceTotals(["0.03"], 20)).toEqual({
      totalHt: "0.03",
      tax: "0.01",
      totalTtc: "0.04",
    });
  });

  test("supports an explicitly configured no-tax rate", () => {
    expect(calculateInvoiceTotals(["100.00"], 0)).toEqual({
      totalHt: "100.00",
      tax: "0.00",
      totalTtc: "100.00",
    });
  });

  test("requires an explicit configured rate", () => {
    expect(() => calculateInvoiceTotals(["100.00"], undefined as never)).toThrow();
  });

  test("formats configured TVA without insignificant trailing zeros", () => {
    expect(formatTaxRate("20.0000")).toBe("20");
    expect(formatTaxRate("7.2500")).toBe("7.25");
  });
});
