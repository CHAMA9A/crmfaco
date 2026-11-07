import { z } from "zod";

const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((value) => value || null);

export const customerInputSchema = z.object({
  customerId: z.string().uuid().nullable().default(null),
  companyName: z.string().trim().min(1, "Le nom de société est obligatoire.").max(200),
  customerCode: z
    .union([
      z.literal(""),
      z
        .string()
        .trim()
        .regex(/^CLI-\d{6,}$/),
    ])
    .transform((v) => v || null),
  contactPerson: optionalText(200),
  phone: optionalText(80),
  whatsapp: optionalText(80),
  email: z.union([z.literal(""), z.string().trim().email().max(320)]).transform((v) => v || null),
  ice: optionalText(80),
  ifNumber: optionalText(80),
  rc: optionalText(80),
  addressLine1: optionalText(500),
  addressLine2: optionalText(500),
  city: optionalText(120),
  postalCode: optionalText(40),
  country: optionalText(120),
  defaultPriceCategory: z.enum(["intercompany", "wholesale", "retail", "custom"]).nullable(),
  notes: optionalText(4000),
  defaultDeliveryAddress: optionalText(500),
  deliveryCity: optionalText(120),
  deliveryContactName: optionalText(200),
  deliveryPhone: optionalText(80),
  deliveryInstructions: optionalText(2000),
  purchaseOrderDefault: optionalText(200),
  externalCustomerId: optionalText(200),
});

export type CustomerInput = z.infer<typeof customerInputSchema>;

export function customerPayload(input: CustomerInput) {
  return {
    company_name: input.companyName,
    customer_code: input.customerCode,
    contact_person: input.contactPerson,
    phone: input.phone,
    whatsapp: input.whatsapp,
    email: input.email,
    ice: input.ice,
    if_number: input.ifNumber,
    rc: input.rc,
    address_line1: input.addressLine1,
    address_line2: input.addressLine2,
    city: input.city,
    postal_code: input.postalCode,
    country: input.country,
    default_price_category: input.defaultPriceCategory,
    notes: input.notes,
    default_delivery_address: input.defaultDeliveryAddress,
    delivery_city: input.deliveryCity,
    delivery_contact_name: input.deliveryContactName,
    delivery_phone: input.deliveryPhone,
    delivery_instructions: input.deliveryInstructions,
    purchase_order_default: input.purchaseOrderDefault,
    external_customer_id: input.externalCustomerId,
  };
}
