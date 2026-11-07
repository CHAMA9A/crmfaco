import { describe, expect, test } from "bun:test";
import { customerInputSchema, customerPayload } from "./validation";

const base = {
  customerId: null,
  companyName: " Client Maroc SARL ",
  customerCode: "",
  contactPerson: "",
  phone: "",
  whatsapp: "",
  email: "",
  ice: "00123",
  ifNumber: "00045",
  rc: "00067",
  addressLine1: "",
  addressLine2: "",
  city: "",
  postalCode: "",
  country: "",
  defaultPriceCategory: "wholesale" as const,
  notes: "",
  defaultDeliveryAddress: "",
  deliveryCity: "",
  deliveryContactName: "",
  deliveryPhone: "",
  deliveryInstructions: "",
  purchaseOrderDefault: "",
  externalCustomerId: "",
};

describe("customer validation", () => {
  test("requires a company name", () => {
    expect(() => customerInputSchema.parse({ ...base, companyName: " " })).toThrow();
  });
  test("keeps legal identifiers as strings with leading zeroes", () => {
    const parsed = customerInputSchema.parse(base);
    expect(customerPayload(parsed).ice).toBe("00123");
    expect(customerPayload(parsed).if_number).toBe("00045");
  });
  test("validates email and customer code", () => {
    expect(() => customerInputSchema.parse({ ...base, email: "bad" })).toThrow();
    expect(() => customerInputSchema.parse({ ...base, customerCode: "CLI-12" })).toThrow();
  });
  test("preserves price category and normalizes empty optional fields", () => {
    const parsed = customerInputSchema.parse(base);
    expect(parsed.defaultPriceCategory).toBe("wholesale");
    expect(parsed.phone).toBeNull();
  });
});
