import { Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { Edit, FileText, Plus, Power } from "lucide-react";
import { PageHeader, StatusBadge } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { addCustomerNoteFn, deactivateCustomerFn } from "@/lib/customers/functions";
import type { CustomerDetailData, CustomerDocument } from "@/lib/customers/types";

const value = (text: string | null | undefined) => text || "—";
const displayDate = (date: string | null | undefined) =>
  date ? new Intl.DateTimeFormat("fr-FR").format(new Date(date)) : "—";

export function CustomerDetail({ data }: { data: CustomerDetailData }) {
  const deactivate = useServerFn(deactivateCustomerFn);
  const addNote = useServerFn(addCustomerNoteFn);
  const [note, setNote] = useState("");
  const [pending, setPending] = useState(false);
  const c = data.customer;
  async function deactivateNow() {
    if (!confirm("Désactiver ce client ? Son historique sera conservé.")) return;
    setPending(true);
    await deactivate({ data: { customerId: c.id } });
    window.location.reload();
  }
  async function submitNote() {
    if (!note.trim()) return;
    setPending(true);
    await addNote({ data: { customerId: c.id, note } });
    window.location.reload();
  }
  return (
    <>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <PageHeader
          eyebrow="Clients"
          title={c.company_name}
          description={`${c.customer_code ?? "Sans code"} · ${c.city ?? "Ville non renseignée"}`}
        />
        <div className="flex gap-2">
          <Button asChild variant="outline">
            <Link to="/facolub/customers/$customerId/edit" params={{ customerId: c.id }}>
              <Edit />
              Modifier
            </Link>
          </Button>
          {c.is_active && (
            <Button variant="outline" disabled={pending} onClick={() => void deactivateNow()}>
              <Power />
              Désactiver
            </Button>
          )}
          <Button asChild>
            <Link to="/facolub/documents/orders/new" search={{ customerId: c.id }}>
              <Plus />
              Nouvelle commande
            </Link>
          </Button>
        </div>
      </div>
      <div className="mb-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <Metric label="Statut">
          <StatusBadge status={c.is_active ? "Active" : "Inactive"} />
        </Metric>
        <Metric label="Catégorie tarifaire" text={value(c.default_price_category)} />
        <Metric label="Tarifs spécifiques" text={String(data.customPriceCount)} />
        <Metric
          label="Documents"
          text={String(
            data.history.orders.length +
              data.history.invoices.length +
              data.history.delivery_notes.length +
              data.history.transport_notes.length,
          )}
        />
      </div>
      <div className="grid gap-5 lg:grid-cols-2">
        <Info
          title="Contact"
          rows={[
            ["Contact", c.contact_person],
            ["Téléphone", c.phone],
            ["WhatsApp", c.whatsapp],
            ["Email", c.email],
          ]}
        />
        <Info
          title="Informations légales"
          rows={[
            ["ICE", c.ice],
            ["IF", c.if_number],
            ["RC", c.rc],
          ]}
        />
        <Info
          title="Adresse"
          rows={[
            ["Adresse", c.address_line1 ?? c.address],
            ["Complément", c.address_line2],
            ["Ville", c.city],
            ["Code postal", c.postal_code],
            ["Pays", c.country],
          ]}
        />
        <Info
          title="Livraison"
          rows={[
            ["Adresse", c.default_delivery_address],
            ["Ville", c.delivery_city],
            ["Contact", c.delivery_contact_name],
            ["Téléphone", c.delivery_phone],
            ["Instructions", c.delivery_instructions],
          ]}
        />
        <Info
          title="Commercial"
          rows={[
            ["Catégorie", c.default_price_category],
            ["PO par défaut", c.purchase_order_default],
            ["Notes", c.notes],
            ["ID externe", c.external_customer_id],
          ]}
        />
      </div>
      <section className="mt-6">
        <h2 className="mb-3 text-xl font-bold">Historique documentaire</h2>
        <div className="grid gap-4 lg:grid-cols-2">
          <Documents title="Commandes" rows={data.history.orders} kind="order" />
          <Documents title="Factures" rows={data.history.invoices} kind="invoice" />
          <Documents title="Bons de livraison" rows={data.history.delivery_notes} kind="delivery" />
          <Documents
            title="Bons de transport"
            rows={data.history.transport_notes}
            kind="transport"
          />
        </div>
      </section>
      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Notes datées</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2">
            <Textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Ajouter une note interne…"
            />
            <Button disabled={pending || !note.trim()} onClick={() => void submitNote()}>
              Ajouter
            </Button>
          </div>
          <div className="mt-4 space-y-3">
            {data.notes.map((entry) => (
              <div key={entry.id} className="rounded-md border p-3">
                <p className="whitespace-pre-wrap text-sm">{entry.note}</p>
                <p className="mt-2 text-xs text-muted-foreground">
                  {displayDate(entry.created_at)}
                </p>
              </div>
            ))}
            {!data.notes.length && (
              <p className="text-sm text-muted-foreground">Aucune note datée.</p>
            )}
          </div>
        </CardContent>
      </Card>
    </>
  );
}

function Metric({
  label,
  text,
  children,
}: {
  label: string;
  text?: string;
  children?: React.ReactNode;
}) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs font-semibold uppercase text-muted-foreground">{label}</p>
        <div className="mt-2 font-bold capitalize">{children ?? text}</div>
      </CardContent>
    </Card>
  );
}
function Info({ title, rows }: { title: string; rows: Array<[string, string | null]> }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="grid gap-3 sm:grid-cols-2">
          {rows.map(([label, text]) => (
            <div key={label}>
              <dt className="text-xs font-semibold uppercase text-muted-foreground">{label}</dt>
              <dd className="mt-1 whitespace-pre-wrap text-sm">{value(text)}</dd>
            </div>
          ))}
        </dl>
      </CardContent>
    </Card>
  );
}
function Documents({
  title,
  rows,
  kind,
}: {
  title: string;
  rows: CustomerDocument[];
  kind: "order" | "invoice" | "delivery" | "transport";
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          <span className="inline-flex items-center gap-2">
            <FileText className="size-4" />
            {title}
          </span>
          <span className="text-sm text-muted-foreground">{rows.length}</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {rows.slice(0, 8).map((row) => {
          const number =
            row.order_number ??
            row.invoice_number ??
            row.delivery_note_number ??
            row.transport_note_number ??
            "Brouillon";
          const content = (
            <div className="flex justify-between rounded-md border p-3 text-sm">
              <span className="font-semibold">{number}</span>
              <span>
                {displayDate(
                  row.order_date ?? row.invoice_date ?? row.delivery_date ?? row.transport_date,
                )}
              </span>
            </div>
          );
          return kind === "order" ? (
            <Link key={row.id} to="/facolub/documents/orders/$orderId" params={{ orderId: row.id }}>
              {content}
            </Link>
          ) : kind === "invoice" ? (
            <Link
              key={row.id}
              to="/facolub/documents/invoices/$invoiceId"
              params={{ invoiceId: row.id }}
            >
              {content}
            </Link>
          ) : (
            <div key={row.id}>{content}</div>
          );
        })}
        {!rows.length && <p className="text-sm text-muted-foreground">Aucun document.</p>}
      </CardContent>
    </Card>
  );
}
