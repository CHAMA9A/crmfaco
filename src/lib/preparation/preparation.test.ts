import { describe, expect, test } from "bun:test";
import { preparationAvailability, type PreparationRequirement } from "./types";

const requirement = (overrides: Partial<PreparationRequirement> = {}): PreparationRequirement => ({
  stock_item_id: crypto.randomUUID(),
  name: "Component",
  category: "label",
  quantity_per_output: 1,
  required_quantity: 100,
  physical_quantity: 200,
  reserved_quantity: 50,
  available_quantity: 150,
  missing_quantity: 0,
  sufficient: true,
  ...overrides,
});

describe("prepared bottle requirement state", () => {
  test("allows confirmation only when every component is sufficient", () => {
    expect(
      preparationAvailability([requirement(), requirement({ category: "empty_bottle" })]),
    ).toEqual({
      sufficient: true,
      missingCount: 0,
    });
  });

  test("counts unavailable components and blocks confirmation", () => {
    expect(
      preparationAvailability([
        requirement(),
        requirement({ available_quantity: 80, missing_quantity: 20, sufficient: false }),
        requirement({ available_quantity: 0, missing_quantity: 100, sufficient: false }),
      ]),
    ).toEqual({ sufficient: false, missingCount: 2 });
  });

  test("does not allow an empty requirement set", () => {
    expect(preparationAvailability([])).toEqual({ sufficient: false, missingCount: 0 });
  });
});
