import { describe, expect, test } from "bun:test";

import {
  calculateAvailableStock,
  calculatePhysicalStock,
  calculateReservedStock,
  canCreateReservation,
  canRecordNormalOut,
  getStockStatus,
  isLowStock,
  stockCapabilities,
  type LedgerEntry,
} from "./types";

describe("stock quantity model", () => {
  test("calculates receipt and outgoing physical movements", () => {
    expect(
      calculatePhysicalStock([
        { direction: "in", quantity: 1000 },
        { direction: "out", quantity: 200 },
        { direction: "out", quantity: 20 },
      ]),
    ).toBe(780);
  });

  test("counts only active reservations", () => {
    expect(
      calculateReservedStock([
        { status: "active", quantity: 700 },
        { status: "released", quantity: 100 },
        { status: "consumed", quantity: 50 },
      ]),
    ).toBe(700);
  });

  test("available equals physical minus reserved", () => {
    expect(calculateAvailableStock(1000, 700)).toBe(300);
  });

  test("a correction appends an inverse effect without changing the original", () => {
    const original: LedgerEntry = { direction: "in", quantity: 5000 };
    const ledger = [original, { direction: "out", quantity: 4500 } satisfies LedgerEntry];
    expect(calculatePhysicalStock(ledger)).toBe(500);
    expect(original).toEqual({ direction: "in", quantity: 5000 });
  });

  test("normal OUT cannot make physical stock negative", () => {
    expect(canRecordNormalOut(100, 100)).toBe(true);
    expect(canRecordNormalOut(100, 101)).toBe(false);
  });

  test("reservation cannot exceed currently available stock", () => {
    expect(canCreateReservation(1000, 700, 300)).toBe(true);
    expect(canCreateReservation(1000, 700, 301)).toBe(false);
  });

  test("sequential reservation checks model the serialized database lock", () => {
    const physical = 1000;
    let reserved = 0;
    expect(canCreateReservation(physical, reserved, 700)).toBe(true);
    reserved += 700;
    expect(canCreateReservation(physical, reserved, 500)).toBe(false);
  });
});

describe("stock semantic status and thresholds", () => {
  test("status always follows quantities", () => {
    expect(getStockStatus(300, 0)).toBe("available");
    expect(getStockStatus(300, 700)).toBe("reserved");
    expect(getStockStatus(0, 700)).toBe("unavailable");
  });

  test("minimum threshold uses available stock", () => {
    expect(isLowStock(199, 200)).toBe(true);
    expect(isLowStock(200, 200)).toBe(false);
    expect(isLowStock(0, null)).toBe(false);
  });
});

describe("stock role capabilities", () => {
  test("Factory can read but cannot mutate stock", () => {
    expect(stockCapabilities("factory")).toEqual({
      read: true,
      recordMovement: false,
      manageReservations: false,
      correctMovement: false,
      configureItems: false,
    });
  });

  test("Management can operate the ledger but cannot configure or correct", () => {
    expect(stockCapabilities("management")).toMatchObject({
      read: true,
      recordMovement: true,
      manageReservations: true,
      correctMovement: false,
      configureItems: false,
    });
  });

  test("Admin has all stock capabilities", () => {
    expect(Object.values(stockCapabilities("admin")).every(Boolean)).toBe(true);
  });
});
