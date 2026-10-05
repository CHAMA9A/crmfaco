import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";

import { InvoiceDocument } from "@/components/invoices/invoice-document";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { issueInvoiceFn } from "@/lib/invoices/functions";
import type { InvoiceDocument as InvoiceData } from "@/lib/invoices/types";
import { updateInvoicePricesFn } from "@/lib/orders/functions";

export function OrderInvoice({
  invoice,
  printable = false,
}: {
  invoice: InvoiceData;
  printable?: boolean;
}) {
  const updatePrices = useServerFn(updateInvoicePricesFn);
  const issue = useServerFn(issueInvoiceFn);
  const [prices, setPrices] = useState<Record<string, string>>(() =>
    Object.fromEntries(
      invoice.items.map((item) => [item.order_item_id ?? item.id, item.unit_price]),
    ),
  );
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const save = async () => {
    setPending(true);
    setError("");
    try {
      await updatePrices({
        data: {
          invoiceId: invoice.id,
          prices: invoice.items.map((item) => ({
            orderItemId: item.order_item_id!,
            unitPrice: prices[item.order_item_id ?? item.id] ?? "0",
          })),
        },
      });
      window.location.reload();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Prix non enregistrés");
      setPending(false);
    }
  };
  const issueNow = async () => {
    setPending(true);
    setError("");
    try {
      await issue({ data: { invoiceId: invoice.id } });
      window.location.reload();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Émission impossible");
      setPending(false);
    }
  };
  return (
    <div className="space-y-5">
      {!printable && invoice.status === "draft" && (
        <section className="border bg-card p-5">
          <h2 className="font-black">Prix de la facture</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Descriptions et quantités proviennent de la commande. Confirmez uniquement les prix
            unitaires.
          </p>
          <div className="mt-4 space-y-3">
            {invoice.items.map((item) => (
              <div
                key={item.id}
                className="grid gap-3 border p-3 sm:grid-cols-[1fr_100px_160px] sm:items-center"
              >
                <div className="font-semibold">{item.description}</div>
                <div className="text-sm">Qté {item.quantity}</div>
                <Input
                  aria-label={`Prix ${item.description}`}
                  type="number"
                  min="0"
                  step="0.01"
                  value={prices[item.order_item_id ?? item.id] ?? ""}
                  onChange={(e) =>
                    setPrices((p) => ({ ...p, [item.order_item_id ?? item.id]: e.target.value }))
                  }
                />
              </div>
            ))}
          </div>
          <div className="mt-4 flex justify-end gap-2">
            <Button variant="outline" disabled={pending} onClick={() => void save()}>
              Enregistrer les prix
            </Button>
            <Button
              disabled={pending || !invoice.prices_confirmed_at}
              onClick={() => void issueNow()}
            >
              Émettre la facture
            </Button>
          </div>
          {error && <p className="mt-3 text-sm font-semibold text-danger">{error}</p>}
        </section>
      )}
      <InvoiceDocument invoice={invoice} printable={printable} />
    </div>
  );
}
