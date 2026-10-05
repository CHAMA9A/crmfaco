import { Link, useRouter } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { Download, Eye, FileText, PackageCheck, Search, ShoppingCart, Truck } from "lucide-react";
import { useMemo, useState } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getInvoiceDocumentFn } from "@/lib/invoices/functions";
import { downloadInvoicePdf } from "@/lib/invoices/pdf";
import {
  confirmOrderFn,
  getDeliveryNoteDocumentFn,
  getTransportNoteDocumentFn,
  prepareBundleFn,
} from "@/lib/orders/functions";
import { downloadDocumentPdf } from "@/lib/orders/pdf";
import type { OrderDocumentSummary, OrderListRow, OrderWorkspaceData } from "@/lib/orders/types";
import type { OrderStatus } from "@/types/database";

const statusLabels: Record<OrderStatus, string> = {
  draft: "Brouillon",
  confirmed: "Confirmée",
  documents_ready: "Documents prêts",
  completed: "Terminée",
  cancelled: "Annulée",
};

const documentStatusLabels: Record<string, string> = {
  draft: "Brouillon",
  issued: "Émis",
  cancelled: "Annulé",
};

type DocumentKind = "invoice" | "delivery" | "transport";

const documentConfig: Record<
  DocumentKind,
  { label: string; path: "invoice" | "delivery-note" | "transport-note"; icon: typeof FileText }
> = {
  invoice: { label: "Facture", path: "invoice", icon: FileText },
  delivery: { label: "Bon de livraison", path: "delivery-note", icon: PackageCheck },
  transport: { label: "Bon de transport", path: "transport-note", icon: Truck },
};

function DocumentCell({
  kind,
  orderId,
  document,
  busy,
  pending,
  onDownload,
}: {
  kind: DocumentKind;
  orderId: string;
  document: OrderDocumentSummary | null;
  busy: boolean;
  pending: boolean;
  onDownload: () => void;
}) {
  const config = documentConfig[kind];
  const Icon = config.icon;
  const href = `/facolub/documents/orders/${orderId}/${config.path}`;
  const openLabel =
    document?.status === "draft"
      ? kind === "invoice"
        ? "Renseigner les prix"
        : "Compléter"
      : "Ouvrir";

  return (
    <article className="rounded-md border bg-background p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2">
          <div className="grid size-8 shrink-0 place-items-center rounded-md bg-secondary text-primary">
            <Icon className="size-4" />
          </div>
          <div className="min-w-0">
            <p className="text-[11px] font-bold uppercase text-muted-foreground">{config.label}</p>
            <p className="mt-0.5 truncate text-sm font-bold">{document?.number ?? "Non préparé"}</p>
          </div>
        </div>
        {document && (
          <Badge variant="secondary">
            {documentStatusLabels[document.status] ?? document.status}
          </Badge>
        )}
      </div>

      {document ? (
        <div className="mt-4 flex flex-wrap gap-2">
          <Button asChild size="sm" variant="outline">
            <a href={href}>{openLabel}</a>
          </Button>
          <Button asChild size="sm" variant="outline">
            <a href={`${href}/preview`}>
              <Eye /> Aperçu
            </a>
          </Button>
          <Button size="sm" disabled={busy} onClick={onDownload}>
            <Download /> {pending ? "Génération…" : "PDF"}
          </Button>
        </div>
      ) : (
        <p className="mt-3 text-xs text-muted-foreground">
          Sera créé avec les documents de cette commande.
        </p>
      )}
    </article>
  );
}

export function OrderWorkspace({ data }: { data: OrderWorkspaceData }) {
  const router = useRouter();
  const confirmOrder = useServerFn(confirmOrderFn);
  const prepareBundle = useServerFn(prepareBundleFn);
  const getInvoice = useServerFn(getInvoiceDocumentFn);
  const getDeliveryNote = useServerFn(getDeliveryNoteDocumentFn);
  const getTransportNote = useServerFn(getTransportNoteDocumentFn);
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState<OrderStatus | "all">("all");
  const [pendingAction, setPendingAction] = useState("");
  const [actionError, setActionError] = useState<{ orderId: string; message: string } | null>(null);

  const rows = useMemo(
    () =>
      data.orders.filter((order) => {
        const haystack = [
          order.order_number,
          order.customer_name,
          order.purchase_order,
          order.invoice?.number,
          order.delivery_note?.number,
          order.transport_note?.number,
          order.order_date,
        ]
          .filter(Boolean)
          .join(" ")
          .toLocaleLowerCase("fr");
        return (
          (status === "all" || order.status === status) &&
          haystack.includes(search.trim().toLocaleLowerCase("fr"))
        );
      }),
    [data.orders, search, status],
  );

  const generateBundle = async (order: OrderListRow) => {
    const actionKey = `bundle:${order.id}`;
    if (pendingAction) return;
    setPendingAction(actionKey);
    setActionError(null);
    try {
      if (order.status === "draft") {
        await confirmOrder({ data: { orderId: order.id } });
      } else {
        await prepareBundle({ data: { orderId: order.id } });
      }
      await router.invalidate();
    } catch (caught) {
      setActionError({
        orderId: order.id,
        message: caught instanceof Error ? caught.message : "Impossible de générer les documents.",
      });
    } finally {
      setPendingAction("");
    }
  };

  const downloadPdf = async (
    order: OrderListRow,
    kind: DocumentKind,
    document: OrderDocumentSummary,
  ) => {
    const actionKey = `pdf:${kind}:${order.id}`;
    if (pendingAction) return;
    setPendingAction(actionKey);
    setActionError(null);
    try {
      if (kind === "invoice") {
        const invoice = await getInvoice({ data: { invoiceId: document.id } });
        await downloadInvoicePdf(invoice);
      } else if (kind === "delivery") {
        const deliveryNote = await getDeliveryNote({ data: { orderId: order.id } });
        await downloadDocumentPdf(deliveryNote, "delivery");
      } else {
        const transportNote = await getTransportNote({ data: { orderId: order.id } });
        await downloadDocumentPdf(transportNote, "transport");
      }
    } catch (caught) {
      setActionError({
        orderId: order.id,
        message: caught instanceof Error ? caught.message : "Impossible de générer le PDF.",
      });
    } finally {
      setPendingAction("");
    }
  };

  return (
    <>
      <PageHeader
        eyebrow="Documents & Dispatch"
        title="Commandes"
        description="Générez, ouvrez et téléchargez la facture, le bon de livraison et le bon de transport de chaque commande."
      />
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-1 gap-2">
          <div className="relative max-w-xl flex-1">
            <Search className="absolute left-3 top-3 size-4 text-muted-foreground" />
            <Input
              className="pl-9"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Commande, client, PO, FAC, BL, BT ou date"
            />
          </div>
          <select
            value={status}
            onChange={(event) => setStatus(event.target.value as OrderStatus | "all")}
            className="h-10 rounded-md border bg-background px-3 text-sm"
          >
            <option value="all">Tous les statuts</option>
            {Object.entries(statusLabels).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </div>
        <Button asChild>
          <Link to="/facolub/documents/orders/new">
            <ShoppingCart /> Nouvelle commande
          </Link>
        </Button>
      </div>

      <div className="grid gap-4">
        {rows.map((order) => {
          const bundleComplete = Boolean(
            order.invoice && order.delivery_note && order.transport_note,
          );
          const canGenerate = order.status !== "cancelled" && !bundleComplete;
          const bundlePending = pendingAction === `bundle:${order.id}`;

          return (
            <article key={order.id} className="border bg-card p-5 shadow-sm">
              <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="text-lg font-black">
                      {order.order_number ?? "Commande brouillon"}
                    </h2>
                    <Badge variant="secondary">{statusLabels[order.status]}</Badge>
                  </div>
                  <p className="mt-1 font-semibold">{order.customer_name}</p>
                  <p className="mt-1 text-sm text-muted-foreground">
                    {order.order_date} · PO {order.purchase_order || "-"}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Button asChild variant="outline">
                    <Link to="/facolub/documents/orders/$orderId" params={{ orderId: order.id }}>
                      Ouvrir la commande
                    </Link>
                  </Button>
                  {canGenerate && (
                    <Button
                      disabled={Boolean(pendingAction)}
                      onClick={() => void generateBundle(order)}
                    >
                      <PackageCheck />
                      {bundlePending
                        ? "Génération…"
                        : order.status === "draft"
                          ? "Confirmer et générer FAC / BL / BT"
                          : "Générer les documents manquants"}
                    </Button>
                  )}
                </div>
              </div>

              {actionError?.orderId === order.id && (
                <p role="alert" className="mt-4 text-sm font-semibold text-danger">
                  {actionError.message}
                </p>
              )}

              <div className="mt-4 grid gap-3 xl:grid-cols-3">
                <DocumentCell
                  kind="invoice"
                  orderId={order.id}
                  document={order.invoice}
                  busy={Boolean(pendingAction)}
                  pending={pendingAction === `pdf:invoice:${order.id}`}
                  onDownload={() =>
                    order.invoice && void downloadPdf(order, "invoice", order.invoice)
                  }
                />
                <DocumentCell
                  kind="delivery"
                  orderId={order.id}
                  document={order.delivery_note}
                  busy={Boolean(pendingAction)}
                  pending={pendingAction === `pdf:delivery:${order.id}`}
                  onDownload={() =>
                    order.delivery_note && void downloadPdf(order, "delivery", order.delivery_note)
                  }
                />
                <DocumentCell
                  kind="transport"
                  orderId={order.id}
                  document={order.transport_note}
                  busy={Boolean(pendingAction)}
                  pending={pendingAction === `pdf:transport:${order.id}`}
                  onDownload={() =>
                    order.transport_note &&
                    void downloadPdf(order, "transport", order.transport_note)
                  }
                />
              </div>
            </article>
          );
        })}

        {rows.length === 0 && (
          <div className="border border-dashed bg-card p-12 text-center text-sm text-muted-foreground">
            Aucune commande ne correspond aux critères.
          </div>
        )}
      </div>
    </>
  );
}
