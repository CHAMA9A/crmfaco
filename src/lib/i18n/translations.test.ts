import { describe, expect, test } from "bun:test";

import { translate } from "./translations";

describe("application translations", () => {
  test("translates known stock labels to French", () => {
    expect(translate("fr", "Physical")).toBe("Physique");
    expect(translate("fr", "Movement history")).toBe("Historique des mouvements");
  });

  test("keeps English source text in English", () => {
    expect(translate("en", "Physical")).toBe("Physical");
  });

  test("falls back safely for dynamic or untranslated content", () => {
    expect(translate("fr", "10W40 5L")).toBe("10W40 5L");
  });
});
