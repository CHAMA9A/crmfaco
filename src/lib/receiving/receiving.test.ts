import { describe, expect, test } from "bun:test";

import {
  buildReceiptStoragePath,
  receiptPhotoMaxBytes,
  sanitizeReceiptFileName,
  validateReceiptLines,
  validateReceiptPhoto,
} from "./types";

describe("receiving form safeguards", () => {
  test("rejects empty, non-positive, and duplicate receipt lines", () => {
    expect(validateReceiptLines([])).toBe("At least one item is required.");
    expect(
      validateReceiptLines([{ key: "1", id: null, stockItemId: "item-a", quantity: "0" }]),
    ).toBe("Every quantity must be greater than zero.");
    expect(
      validateReceiptLines([
        { key: "1", id: null, stockItemId: "item-a", quantity: "1" },
        { key: "2", id: null, stockItemId: "item-a", quantity: "2" },
      ]),
    ).toBe("Each item can appear only once.");
  });

  test("accepts a valid multi-line draft", () => {
    expect(
      validateReceiptLines([
        { key: "1", id: null, stockItemId: "item-a", quantity: "2000" },
        { key: "2", id: null, stockItemId: "item-b", quantity: "25.5" },
      ]),
    ).toBeNull();
  });

  test("validates private receipt photo inputs", () => {
    expect(validateReceiptPhoto({ type: "image/jpeg", size: 1024 })).toBeNull();
    expect(validateReceiptPhoto({ type: "application/pdf", size: 1024 })).toContain("JPEG");
    expect(validateReceiptPhoto({ type: "image/png", size: receiptPhotoMaxBytes + 1 })).toContain(
      "8 MiB",
    );
  });

  test("builds receipt-scoped safe storage paths", () => {
    expect(sanitizeReceiptFileName(" arrivage été #1.jpg ")).toBe("arrivage-ete-1.jpg");
    expect(buildReceiptStoragePath("receipt-id", "photo stock.jpg", "token")).toBe(
      "receipt-id/token-photo-stock.jpg",
    );
  });
});
