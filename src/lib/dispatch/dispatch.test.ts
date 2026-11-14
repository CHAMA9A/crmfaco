import { describe, expect, test } from "bun:test";
import { fulfillmentState, sanitizeDispatchFileName, validateLoadedQuantity } from "./types";

describe("dispatch validation", () => {
  test("rejects zero, invalid and over-dispatch quantities", () => {
    expect(validateLoadedQuantity(0, 50)).toBeTruthy();
    expect(validateLoadedQuantity("nope", 50)).toBeTruthy();
    expect(validateLoadedQuantity(51, 50)).toBeTruthy();
    expect(validateLoadedQuantity(50, 50)).toBeNull();
  });
  test("derives fulfillment independently from commercial order status", () => {
    expect(fulfillmentState([{ ordered: 500, dispatched: 0 }])).toBe("not_dispatched");
    expect(fulfillmentState([{ ordered: 500, dispatched: 450 }])).toBe("partially_dispatched");
    expect(fulfillmentState([{ ordered: 500, dispatched: 500 }])).toBe("fully_dispatched");
  });
  test("builds storage-safe names", () => {
    expect(sanitizeDispatchFileName("immatriculation été 1.jpg")).toBe("immatriculation-ete-1.jpg");
  });
});
