import { CheckCircle2, FileText, PackageCheck, Truck } from "lucide-react";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { confirmOrderFn, prepareBundleFn } from "@/lib/orders/functions";
import type { OrderDetailData, OrderDocumentSummary } from "@/lib/orders/types";

function DocCard({
  title,
  icon: Icon,
  document,
  href,
}: {
  title: string;
  icon: typeof FileText;
  document: OrderDocumentSummary | null;
  href: string;
}) {
  return (
    <article className="border bg-card p-5 shadow-sm">
      <div className="flex items-start justify-between">
        <div className="grid size-10 place-items-center rounded-md bg-secondary text-primary">
          <Icon className="size-5" />
        </div>
        <Badge variant="secondary">{document?.status ?? "non préparé"}</Badge>
      </div>
      <h3 className="mt-4 font-black">{title}</h3>
      <p className="mt-1 text-sm text-muted-foreground">{document?.number ?? "Aucun document"}</p>
      <div className="mt-5 flex gap-2">
        {document && (
          <>
            <Button asChild size="sm">
              <a href={href}>Ouvrir</a>
            </Button>
            <Button asChild size="sm" variant="outline">
              <a href={`${href}/preview`}>Aperçu</a>
            </Button>
          </>
        )}
      </div>
    </article>
  );
}

export function OrderDetail({ data }: { data: OrderDetailData }) {
  const confirm = useServerFn(confirmOrderFn);
  const prepare = useServerFn(prepareBundleFn);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const run = async (action: "confirm" | "prepare") => {
    setPending(true);
    setError("");
    try {
      if (action === "confirm") await confirm({ data: { orderId: data.order.id } });
      else await prepare({ data: { orderId: data.order.id } });
      window.location.reload();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Action impossible");
      setPending(false);
    }
  };
  const base = `/facolub/documents/orders/${data.order.id}`;
  return (
    <>
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <PageHeader
          eyebrow="Commandes"
          title={data.order.order_number ?? "Commande brouillon"}
          description={`${data.order.customer_name} · ${data.order.order_date}`}
        />
        <div className="flex gap-2">
          {data.order.status === "draft" ? (
            <>
              <Button asChild variant="outline">
                <a href={`${base}/edit`}>Modifier</a>
              </Button>
              <Button disabled={pending} onClick={() => void run("confirm")}>
                <CheckCircle2 /> Confirmer et préparer
              </Button>
            </>
          ) : (
            <Button variant="outline" disabled={pending} onClick={() => void run("prepare")}>
              <PackageCheck /> Préparer les documents
            </Button>
          )}
        </div>
      </div>
      {error && <p className="mb-4 text-sm font-semibold text-danger">{error}</p>}
      <section className="grid gap-4 border bg-card p-5 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <p className="text-xs font-bold uppercase text-muted-foreground">Client</p>
          <p className="mt-1 font-semibold">{data.order.customer_name}</p>
        </div>
        <div>
          <p className="text-xs font-bold uppercase text-muted-foreground">PO</p>
          <p className="mt-1 font-semibold">{data.order.purchase_order || "—"}</p>
        </div>
        <div>
          <p className="text-xs font-bold uppercase text-muted-foreground">Destination</p>
          <p className="mt-1 font-semibold">{data.order.destination_city || "—"}</p>
        </div>
        <div>
          <p className="text-xs font-bold uppercase text-muted-foreground">Statut</p>
          <p className="mt-1 font-semibold">{data.order.status}</p>
        </div>
        <div className="sm:col-span-2 lg:col-span-4">
          <p className="text-xs font-bold uppercase text-muted-foreground">Adresse</p>
          <p className="mt-1 text-sm">{data.order.destination_address || "—"}</p>
        </div>
      </section>
      <section className="mt-7">
        <h2 className="mb-3 text-lg font-black">Produits</h2>
        <div className="overflow-hidden border bg-card">
          <table className="w-full text-sm">
            <thead className="bg-secondary text-left text-xs uppercase">
              <tr>
                <th className="px-4 py-3">Description</th>
                <th className="px-4 py-3 text-right">Quantité</th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {data.items.map((item) => (
                <tr key={item.id}>
                  <td className="px-4 py-3">{item.description}</td>
                  <td className="px-4 py-3 text-right font-bold">{item.quantity}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <section className="mt-7">
        <h2 className="mb-3 text-lg font-black">Documents</h2>
        <div className="grid gap-4 lg:grid-cols-3">
          <DocCard
            title="Facture"
            icon={FileText}
            document={data.invoice}
            href={`${base}/invoice`}
          />
          <DocCard
            title="Bon de livraison"
            icon={PackageCheck}
            document={data.delivery_note}
            href={`${base}/delivery-note`}
          />
          <DocCard
            title="Bon de transport"
            icon={Truck}
            document={data.transport_note}
            href={`${base}/transport-note`}
          />
        </div>
      </section>
    </>
  );
}
