import { Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { Download, Eye, FilePlus2, Plus, Printer, Send, Trash2, UserPlus } from "lucide-react";
import { useRef, useState, type FormEvent } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  createCustomerFn,
  createInvoiceDraftFn,
  getInvoiceDocumentFn,
  issueInvoiceFn,
} from "@/lib/invoices/functions";
import { formatMad } from "@/lib/invoices/money";
import {
  downloadInvoicePdf,
  previewInvoicePdf,
  reserveInvoicePdfPreview,
} from "@/lib/invoices/pdf";
import type {
  InvoiceStatus,
  InvoiceWorkspaceCustomer,
  InvoiceWorkspaceData,
} from "@/lib/invoices/types";
import { cn } from "@/lib/utils";

type DraftLine = {
  id: number;
  description: string;
  quantity: string;
  unitPrice: string;
};

const initialLine: DraftLine = { id: 1, description: "", quantity: "1", unitPrice: "" };

function statusLabel(status: InvoiceStatus) {
  if (status === "issued") return "Émise";
  if (status === "cancelled") return "Annulée";
  return "Brouillon";
}

function InvoiceStatusBadge({ status }: { status: InvoiceStatus }) {
  return (
    <span
      className={cn(
        "inline-flex rounded-full px-2.5 py-1 text-xs font-bold",
        status === "issued" && "bg-success-soft text-success",
        status === "draft" && "bg-warning-soft text-warning",
        status === "cancelled" && "bg-danger-soft text-danger",
      )}
    >
      {statusLabel(status)}
    </span>
  );
}

export function InvoiceWorkspace({ data }: { data: InvoiceWorkspaceData }) {
  const createCustomer = useServerFn(createCustomerFn);
  const createInvoice = useServerFn(createInvoiceDraftFn);
  const issueInvoice = useServerFn(issueInvoiceFn);
  const getInvoiceDocument = useServerFn(getInvoiceDocumentFn);
  const nextLineId = useRef(2);

  const [customers, setCustomers] = useState(data.customers);
  const [customerId, setCustomerId] = useState("");
  const [invoiceDate, setInvoiceDate] = useState(data.today);
  const [purchaseOrder, setPurchaseOrder] = useState("");
  const [lines, setLines] = useState<DraftLine[]>([initialLine]);
  const [creatingCustomer, setCreatingCustomer] = useState(false);
  const [creatingInvoice, setCreatingInvoice] = useState(false);
  const [issuingId, setIssuingId] = useState<string | null>(null);
  const [pdfInvoiceId, setPdfInvoiceId] = useState<string | null>(null);
  const [customerError, setCustomerError] = useState("");
  const [invoiceError, setInvoiceError] = useState("");

  const selectedCustomer = customers.find((customer) => customer.id === customerId) ?? null;
  const indicativeTotal = lines.reduce((sum, line) => {
    const quantity = Number(line.quantity);
    const unitPrice = Number(line.unitPrice);
    return Number.isFinite(quantity) && Number.isFinite(unitPrice)
      ? sum + quantity * unitPrice
      : sum;
  }, 0);

  const selectCustomer = (id: string) => {
    setCustomerId(id);
    const customer = customers.find((item) => item.id === id);
    setPurchaseOrder(customer?.purchase_order_default ?? "");
  };

  const updateLine = (id: number, field: keyof Omit<DraftLine, "id">, value: string) => {
    setLines((current) =>
      current.map((line) => (line.id === id ? { ...line, [field]: value } : line)),
    );
  };

  const addLine = () => {
    const id = nextLineId.current;
    nextLineId.current += 1;
    setLines((current) => [...current, { id, description: "", quantity: "1", unitPrice: "" }]);
  };

  const removeLine = (id: number) => {
    setLines((current) =>
      current.length === 1 ? current : current.filter((line) => line.id !== id),
    );
  };

  const submitCustomer = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (creatingCustomer) return;
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    setCreatingCustomer(true);
    setCustomerError("");
    try {
      const customer = await createCustomer({
        data: {
          companyName: String(form.get("companyName") ?? ""),
          contactPerson: String(form.get("contactPerson") ?? ""),
          phone: String(form.get("phone") ?? ""),
          email: String(form.get("email") ?? ""),
          city: String(form.get("city") ?? ""),
          address: String(form.get("address") ?? ""),
          ice: String(form.get("ice") ?? ""),
          purchaseOrderDefault: String(form.get("purchaseOrderDefault") ?? ""),
        },
      });
      setCustomers((current) =>
        [...current, customer].sort((a, b) => a.company_name.localeCompare(b.company_name)),
      );
      setCustomerId(customer.id);
      setPurchaseOrder(customer.purchase_order_default ?? "");
      formElement.reset();
    } catch {
      setCustomerError("Impossible de créer le client. Vérifiez les champs et réessayez.");
    } finally {
      setCreatingCustomer(false);
    }
  };

  const submitInvoice = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (creatingInvoice) return;
    if (!customerId) {
      setInvoiceError("Sélectionnez un client actif.");
      return;
    }
    setCreatingInvoice(true);
    setInvoiceError("");
    try {
      const invoice = await createInvoice({
        data: {
          customerId,
          invoiceDate,
          purchaseOrder,
          items: lines.map((line) => ({
            description: line.description,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
          })),
        },
      });
      window.location.assign(`/facolub/documents/invoices/${invoice.id}`);
    } catch {
      setInvoiceError(
        "Impossible de créer la facture. Vérifiez le client, les quantités et les prix.",
      );
    } finally {
      setCreatingInvoice(false);
    }
  };

  const issueDraft = async (invoiceId: string) => {
    if (issuingId) return;
    if (!window.confirm("Émettre cette facture et lui attribuer son numéro officiel ?")) return;
    setIssuingId(invoiceId);
    try {
      await issueInvoice({ data: { invoiceId } });
      window.location.reload();
    } catch {
      setInvoiceError(
        "La facture n’a pas pu être émise. Vérifiez qu’elle est toujours en brouillon.",
      );
      setIssuingId(null);
    }
  };

  const previewPdf = async (invoiceId: string) => {
    if (pdfInvoiceId) return;
    const preview = reserveInvoicePdfPreview();
    setPdfInvoiceId(invoiceId);
    setInvoiceError("");
    try {
      const invoice = await getInvoiceDocument({ data: { invoiceId } });
      await previewInvoicePdf(invoice, preview);
    } catch {
      preview?.close();
      setInvoiceError("Impossible de générer l’aperçu PDF. Ouvrez la facture et réessayez.");
    } finally {
      setPdfInvoiceId(null);
    }
  };

  const downloadPdf = async (invoiceId: string) => {
    if (pdfInvoiceId) return;
    setPdfInvoiceId(invoiceId);
    setInvoiceError("");
    try {
      const invoice = await getInvoiceDocument({ data: { invoiceId } });
      await downloadInvoicePdf(invoice);
    } catch {
      setInvoiceError("Impossible de télécharger le PDF. Ouvrez la facture et réessayez.");
    } finally {
      setPdfInvoiceId(null);
    }
  };

  return (
    <>
      <PageHeader
        title="Factures"
        description="Créez les factures SOMA en MAD. Les totaux définitifs et les numéros officiels sont calculés par la base de données."
        eyebrow="Documents"
      />

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1.35fr)_minmax(320px,.65fr)]">
        <section className="border border-border bg-card p-5 shadow-sm sm:p-6">
          <div className="mb-6 flex items-start gap-3">
            <div className="grid size-10 shrink-0 place-items-center rounded-md bg-primary text-primary-foreground">
              <FilePlus2 className="size-5" />
            </div>
            <div>
              <h2 className="text-lg font-bold">Nouvelle facture</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Enregistrez d’abord le brouillon, puis contrôlez-le avant émission.
              </p>
            </div>
          </div>

          <form onSubmit={submitInvoice} className="space-y-6">
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="invoice-customer">Client actif</Label>
                <select
                  id="invoice-customer"
                  value={customerId}
                  onChange={(event) => selectCustomer(event.target.value)}
                  required
                  className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
                >
                  <option value="">Sélectionner un client</option>
                  {customers.map((customer) => (
                    <option key={customer.id} value={customer.id}>
                      {customer.company_name}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="invoice-date">Date</Label>
                <Input
                  id="invoice-date"
                  type="date"
                  value={invoiceDate}
                  onChange={(event) => setInvoiceDate(event.target.value)}
                  required
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="purchase-order">Commande (PO)</Label>
              <Input
                id="purchase-order"
                value={purchaseOrder}
                onChange={(event) => setPurchaseOrder(event.target.value)}
                maxLength={200}
                placeholder="Facultatif"
              />
            </div>

            {selectedCustomer && (
              <div className="grid gap-2 border border-dashed border-border bg-secondary/35 p-4 text-sm sm:grid-cols-2">
                <p>
                  <strong>Ville :</strong> {selectedCustomer.city || "—"}
                </p>
                <p>
                  <strong>ICE :</strong> {selectedCustomer.ice || "—"}
                </p>
                <p className="sm:col-span-2">
                  <strong>Adresse :</strong> {selectedCustomer.address || "—"}
                </p>
              </div>
            )}

            <div>
              <div className="mb-3 flex items-center justify-between gap-3">
                <div>
                  <h3 className="font-bold">Lignes de produits</h3>
                  <p className="text-xs text-muted-foreground">Prix saisis manuellement.</p>
                </div>
                <Button type="button" variant="outline" size="sm" onClick={addLine}>
                  <Plus /> Ajouter une ligne
                </Button>
              </div>
              <div className="space-y-3">
                {lines.map((line, index) => (
                  <div
                    key={line.id}
                    className="grid gap-3 border border-border bg-background p-3 md:grid-cols-[minmax(0,1fr)_120px_150px_auto] md:items-end"
                  >
                    <div className="space-y-2">
                      <Label htmlFor={`line-description-${line.id}`}>Description {index + 1}</Label>
                      <Input
                        id={`line-description-${line.id}`}
                        value={line.description}
                        onChange={(event) => updateLine(line.id, "description", event.target.value)}
                        maxLength={500}
                        required
                        placeholder="Produit ou prestation"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor={`line-quantity-${line.id}`}>Quantité</Label>
                      <Input
                        id={`line-quantity-${line.id}`}
                        type="number"
                        min="0.001"
                        step="0.001"
                        value={line.quantity}
                        onChange={(event) => updateLine(line.id, "quantity", event.target.value)}
                        required
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor={`line-price-${line.id}`}>Prix unitaire MAD</Label>
                      <Input
                        id={`line-price-${line.id}`}
                        type="number"
                        min="0"
                        step="0.01"
                        value={line.unitPrice}
                        onChange={(event) => updateLine(line.id, "unitPrice", event.target.value)}
                        required
                      />
                    </div>
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      disabled={lines.length === 1}
                      onClick={() => removeLine(line.id)}
                      aria-label={`Supprimer la ligne ${index + 1}`}
                    >
                      <Trash2 />
                    </Button>
                  </div>
                ))}
              </div>
            </div>

            <div className="flex flex-col gap-4 border-t pt-5 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-xs font-bold uppercase text-muted-foreground">Total indicatif</p>
                <p className="mt-1 text-xl font-black">{formatMad(indicativeTotal.toFixed(2))}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Le total officiel sera recalculé par la base après enregistrement.
                </p>
              </div>
              <Button type="submit" size="lg" disabled={creatingInvoice || customers.length === 0}>
                <FilePlus2 />
                {creatingInvoice ? "Enregistrement…" : "Enregistrer le brouillon"}
              </Button>
            </div>
            {invoiceError && (
              <p role="alert" className="text-sm font-semibold text-danger">
                {invoiceError}
              </p>
            )}
          </form>
        </section>

        <aside className="space-y-6">
          <details className="border border-border bg-card shadow-sm" open={customers.length === 0}>
            <summary className="flex cursor-pointer list-none items-center gap-3 p-5 font-bold [&::-webkit-details-marker]:hidden">
              <UserPlus className="size-5 text-primary" />
              Ajouter un client
            </summary>
            <form onSubmit={submitCustomer} className="space-y-4 border-t p-5">
              <div className="space-y-2">
                <Label htmlFor="customer-company">Raison sociale *</Label>
                <Input id="customer-company" name="companyName" required maxLength={200} />
              </div>
              <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-1">
                <div className="space-y-2">
                  <Label htmlFor="customer-contact">Contact</Label>
                  <Input id="customer-contact" name="contactPerson" maxLength={200} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="customer-phone">Téléphone</Label>
                  <Input id="customer-phone" name="phone" maxLength={50} />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="customer-email">Email</Label>
                <Input id="customer-email" name="email" type="email" maxLength={254} />
              </div>
              <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-1">
                <div className="space-y-2">
                  <Label htmlFor="customer-city">Ville</Label>
                  <Input id="customer-city" name="city" maxLength={120} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="customer-ice">ICE</Label>
                  <Input id="customer-ice" name="ice" maxLength={100} />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="customer-address">Adresse</Label>
                <Textarea id="customer-address" name="address" maxLength={500} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="customer-po">PO par défaut</Label>
                <Input id="customer-po" name="purchaseOrderDefault" maxLength={200} />
              </div>
              <Button type="submit" className="w-full" disabled={creatingCustomer}>
                <UserPlus />
                {creatingCustomer ? "Création…" : "Créer le client"}
              </Button>
              {customerError && (
                <p role="alert" className="text-sm font-semibold text-danger">
                  {customerError}
                </p>
              )}
            </form>
          </details>

          <div className="border-l-4 border-info bg-info-soft p-4 text-sm text-info">
            <p className="font-bold">Règle commerciale actuelle</p>
            <p className="mt-1 leading-6">Un seul montant commercial final est utilisé : TOTAL.</p>
          </div>
        </aside>
      </div>

      <section className="mt-8">
        <div className="mb-3 flex items-end justify-between gap-4">
          <div>
            <h2 className="text-lg font-bold">Factures récentes</h2>
            <p className="text-sm text-muted-foreground">Les 50 dernières factures accessibles.</p>
          </div>
          <span className="text-xs font-bold text-muted-foreground">
            {data.invoices.length} facture(s)
          </span>
        </div>
        <div className="overflow-x-auto border border-border bg-card shadow-sm">
          <table className="w-full min-w-[860px] text-left text-sm">
            <thead className="border-b bg-secondary/60 text-xs uppercase text-muted-foreground">
              <tr>
                <th className="px-4 py-3">Facture</th>
                <th className="px-4 py-3">Date</th>
                <th className="px-4 py-3">Client</th>
                <th className="px-4 py-3">PO</th>
                <th className="px-4 py-3 text-right">Total</th>
                <th className="px-4 py-3">Statut</th>
                <th className="px-4 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {data.invoices.map((invoice) => (
                <tr key={invoice.id}>
                  <td className="px-4 py-4 font-bold">{invoice.invoice_number ?? "Brouillon"}</td>
                  <td className="px-4 py-4">{invoice.invoice_date}</td>
                  <td className="px-4 py-4">{invoice.customer_name_snapshot}</td>
                  <td className="px-4 py-4 text-muted-foreground">
                    {invoice.purchase_order || "—"}
                  </td>
                  <td className="px-4 py-4 text-right font-bold">{formatMad(invoice.total)}</td>
                  <td className="px-4 py-4">
                    <InvoiceStatusBadge status={invoice.status} />
                  </td>
                  <td className="px-4 py-4">
                    <div className="flex justify-end gap-2">
                      {invoice.status === "draft" && (
                        <Button
                          type="button"
                          size="sm"
                          onClick={() => void issueDraft(invoice.id)}
                          disabled={issuingId !== null}
                        >
                          <Send />
                          {issuingId === invoice.id ? "Émission…" : "Émettre"}
                        </Button>
                      )}
                      <Button asChild variant="outline" size="icon" aria-label="Voir la facture">
                        <Link
                          to="/facolub/documents/invoices/$invoiceId"
                          params={{ invoiceId: invoice.id }}
                        >
                          <Eye />
                        </Link>
                      </Button>
                      <Button
                        type="button"
                        variant="outline"
                        size="icon"
                        aria-label="Aperçu PDF"
                        title="Aperçu PDF"
                        disabled={pdfInvoiceId !== null}
                        onClick={() => void previewPdf(invoice.id)}
                      >
                        <Printer />
                      </Button>
                      <Button
                        type="button"
                        variant="outline"
                        size="icon"
                        aria-label="Télécharger le PDF"
                        title="Télécharger le PDF"
                        disabled={pdfInvoiceId !== null}
                        onClick={() => void downloadPdf(invoice.id)}
                      >
                        <Download />
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {data.invoices.length === 0 && (
            <p className="p-10 text-center text-sm text-muted-foreground">
              Aucune facture. Utilisez le formulaire ci-dessus pour créer le premier brouillon.
            </p>
          )}
        </div>
      </section>
    </>
  );
}
