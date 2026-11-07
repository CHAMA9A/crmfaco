import { Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { AlertTriangle } from "lucide-react";
import { PageHeader } from "@/components/app/facolub-ui";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { getCustomerPossibleDuplicatesFn, saveCustomerFn } from "@/lib/customers/functions";
import type { CustomerDuplicate } from "@/lib/customers/types";
import type { Customer } from "@/types/database";

const field = (form: FormData, name: string) => String(form.get(name) ?? "");

export function CustomerForm({ customer = null }: { customer?: Customer | null }) {
  const save = useServerFn(saveCustomerFn);
  const checkDuplicates = useServerFn(getCustomerPossibleDuplicatesFn);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [duplicates, setDuplicates] = useState<CustomerDuplicate[]>([]);
  const [duplicateConfirmed, setDuplicateConfirmed] = useState(false);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setError("");
    const form = new FormData(event.currentTarget);
    const input = {
      customerId: customer?.id ?? null,
      companyName: field(form, "companyName"),
      customerCode: field(form, "customerCode"),
      contactPerson: field(form, "contactPerson"),
      phone: field(form, "phone"),
      whatsapp: field(form, "whatsapp"),
      email: field(form, "email"),
      ice: field(form, "ice"),
      ifNumber: field(form, "ifNumber"),
      rc: field(form, "rc"),
      addressLine1: field(form, "addressLine1"),
      addressLine2: field(form, "addressLine2"),
      city: field(form, "city"),
      postalCode: field(form, "postalCode"),
      country: field(form, "country"),
      defaultPriceCategory: (field(form, "defaultPriceCategory") || null) as
        "intercompany" | "wholesale" | "retail" | "custom" | null,
      notes: field(form, "notes"),
      defaultDeliveryAddress: field(form, "defaultDeliveryAddress"),
      deliveryCity: field(form, "deliveryCity"),
      deliveryContactName: field(form, "deliveryContactName"),
      deliveryPhone: field(form, "deliveryPhone"),
      deliveryInstructions: field(form, "deliveryInstructions"),
      purchaseOrderDefault: field(form, "purchaseOrderDefault"),
      externalCustomerId: field(form, "externalCustomerId"),
    };
    try {
      if (!duplicateConfirmed) {
        const matches = await checkDuplicates({
          data: {
            customerId: input.customerId,
            companyName: input.companyName,
            ice: input.ice || null,
            email: input.email || null,
            phone: input.phone || null,
          },
        });
        if (matches.length) {
          setDuplicates(matches);
          setPending(false);
          return;
        }
      }
      const saved = await save({ data: input });
      window.location.assign(`/facolub/customers/${saved.id}`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Impossible d’enregistrer le client.");
      setPending(false);
    }
  }

  const input = (name: keyof Customer, fallback = "") =>
    customer?.[name] == null ? fallback : String(customer[name]);
  return (
    <>
      <PageHeader
        eyebrow="Clients"
        title={customer ? "Modifier le client" : "Nouveau client"}
        description="Le nom de société est le seul champ obligatoire. Les identifiants légaux restent du texte afin de préserver les zéros initiaux."
      />
      {duplicates.length > 0 && (
        <Alert className="mb-5 border-warning">
          <AlertTriangle />
          <AlertTitle>Client potentiellement en double</AlertTitle>
          <AlertDescription>
            <p>Vérifiez ces fiches avant de continuer :</p>
            <ul className="mt-2 list-disc pl-5">
              {duplicates.map((match) => (
                <li key={match.id}>
                  <Link
                    className="underline"
                    to="/facolub/customers/$customerId"
                    params={{ customerId: match.id }}
                  >
                    {match.company_name}
                  </Link>{" "}
                  — correspondance : {match.matched_on.join(", ")}
                </li>
              ))}
            </ul>
            <Button
              type="button"
              className="mt-3"
              variant="outline"
              onClick={() => {
                setDuplicateConfirmed(true);
                setDuplicates([]);
              }}
            >
              Ce n’est pas un doublon, continuer
            </Button>
          </AlertDescription>
        </Alert>
      )}
      <form onSubmit={submit} className="space-y-6">
        <Section title="Identité">
          <Field
            label="Société *"
            name="companyName"
            required
            defaultValue={input("company_name")}
          />
          <Field
            label="Code client (généré automatiquement)"
            name="customerCode"
            pattern="CLI-[0-9]{6,}"
            defaultValue={input("customer_code")}
          />
          <SelectField
            label="Catégorie tarifaire"
            name="defaultPriceCategory"
            defaultValue={input("default_price_category")}
          />
          <Field
            label="Identifiant externe (futur site)"
            name="externalCustomerId"
            defaultValue={input("external_customer_id")}
          />
        </Section>
        <Section title="Contact">
          <Field
            label="Personne à contacter"
            name="contactPerson"
            defaultValue={input("contact_person")}
          />
          <Field label="Téléphone" name="phone" type="tel" defaultValue={input("phone")} />
          <Field label="WhatsApp" name="whatsapp" type="tel" defaultValue={input("whatsapp")} />
          <Field label="Email" name="email" type="email" defaultValue={input("email")} />
        </Section>
        <Section title="Informations légales">
          <Field label="ICE" name="ice" defaultValue={input("ice")} />
          <Field label="IF" name="ifNumber" defaultValue={input("if_number")} />
          <Field label="RC" name="rc" defaultValue={input("rc")} />
        </Section>
        <Section title="Adresse">
          <Field
            label="Adresse"
            name="addressLine1"
            defaultValue={input("address_line1", input("address"))}
          />
          <Field label="Complément" name="addressLine2" defaultValue={input("address_line2")} />
          <Field label="Ville" name="city" defaultValue={input("city")} />
          <Field label="Code postal" name="postalCode" defaultValue={input("postal_code")} />
          <Field label="Pays" name="country" defaultValue={input("country")} />
        </Section>
        <Section title="Livraison">
          <Field
            label="Adresse de livraison par défaut"
            name="defaultDeliveryAddress"
            defaultValue={input("default_delivery_address")}
          />
          <Field
            label="Ville de livraison"
            name="deliveryCity"
            defaultValue={input("delivery_city")}
          />
          <Field
            label="Contact livraison"
            name="deliveryContactName"
            defaultValue={input("delivery_contact_name")}
          />
          <Field
            label="Téléphone livraison"
            name="deliveryPhone"
            type="tel"
            defaultValue={input("delivery_phone")}
          />
          <Area
            label="Instructions de livraison"
            name="deliveryInstructions"
            defaultValue={input("delivery_instructions")}
          />
        </Section>
        <Section title="Commercial">
          <Field
            label="PO par défaut"
            name="purchaseOrderDefault"
            defaultValue={input("purchase_order_default")}
          />
          <Area label="Notes générales" name="notes" defaultValue={input("notes")} />
        </Section>
        {error && (
          <p role="alert" className="text-sm font-semibold text-danger">
            {error}
          </p>
        )}
        <div className="flex justify-end gap-3">
          <Button asChild type="button" variant="outline">
            <Link
              to={customer ? "/facolub/customers/$customerId" : "/facolub/customers"}
              params={customer ? { customerId: customer.id } : {}}
            >
              Annuler
            </Link>
          </Button>
          <Button disabled={pending}>
            {pending ? "Enregistrement…" : "Enregistrer le client"}
          </Button>
        </div>
      </form>
    </>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border bg-card p-5">
      <h2 className="mb-4 text-lg font-bold">{title}</h2>
      <div className="grid gap-4 md:grid-cols-2">{children}</div>
    </section>
  );
}
function Field({
  label,
  name,
  ...props
}: { label: string; name: string } & React.ComponentProps<typeof Input>) {
  return (
    <div className="space-y-2">
      <Label htmlFor={name}>{label}</Label>
      <Input id={name} name={name} maxLength={500} {...props} />
    </div>
  );
}
function Area({
  label,
  name,
  ...props
}: { label: string; name: string } & React.ComponentProps<typeof Textarea>) {
  return (
    <div className="space-y-2 md:col-span-2">
      <Label htmlFor={name}>{label}</Label>
      <Textarea id={name} name={name} maxLength={4000} {...props} />
    </div>
  );
}
function SelectField({
  label,
  name,
  defaultValue,
}: {
  label: string;
  name: string;
  defaultValue: string;
}) {
  return (
    <div className="space-y-2">
      <Label htmlFor={name}>{label}</Label>
      <select
        id={name}
        name={name}
        defaultValue={defaultValue}
        className="h-10 w-full rounded-md border bg-background px-3"
      >
        <option value="">Non définie</option>
        <option value="intercompany">Intercompany</option>
        <option value="wholesale">Wholesale</option>
        <option value="retail">Retail</option>
        <option value="custom">Custom</option>
      </select>
    </div>
  );
}
