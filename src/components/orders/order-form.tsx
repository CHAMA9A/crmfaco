import { Minus, Plus } from "lucide-react";
import { useServerFn } from "@tanstack/react-start";
import { useState, type FormEvent } from "react";

import { PageHeader } from "@/components/app/facolub-ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { createOrderFn, updateOrderFn } from "@/lib/orders/functions";
import type { DraftOrderEditorData, OrderEditorData } from "@/lib/orders/types";

type Line = { key: number; description: string; quantity: string };

export function OrderForm({ data }: { data: OrderEditorData | DraftOrderEditorData }) {
  const createOrder = useServerFn(createOrderFn);
  const updateOrder = useServerFn(updateOrderFn);
  const existing = "order" in data ? data : null;
  const [customerId, setCustomerId] = useState(existing?.order.customer_id ?? "");
  const [date, setDate] = useState(existing?.order.order_date ?? data.today);
  const [po, setPo] = useState(existing?.order.purchase_order ?? "");
  const [city, setCity] = useState(existing?.order.destination_city ?? "");
  const [address, setAddress] = useState(existing?.order.destination_address ?? "");
  const [lines, setLines] = useState<Line[]>(
    existing
      ? existing.items.map((item, index) => ({
          key: index + 1,
          description: item.description,
          quantity: item.quantity,
        }))
      : [{ key: 1, description: "", quantity: "1" }],
  );
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const chooseCustomer = (id: string) => {
    setCustomerId(id);
    const c = data.customers.find((x) => x.id === id);
    setPo(c?.purchase_order_default ?? "");
    setCity(c?.city ?? "");
    setAddress(c?.address ?? "");
  };
  const updateLine = (key: number, field: "description" | "quantity", value: string) =>
    setLines((current) =>
      current.map((line) => (line.key === key ? { ...line, [field]: value } : line)),
    );
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (pending) return;
    setPending(true);
    setError("");
    try {
      const payload = {
        customerId,
        orderDate: date,
        purchaseOrder: po,
        destinationCity: city,
        destinationAddress: address,
        items: lines,
      };
      const order = existing
        ? await updateOrder({ data: { ...payload, orderId: existing.order.id } })
        : await createOrder({ data: payload });
      window.location.assign(`/facolub/documents/orders/${order.id}`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Impossible de créer la commande.");
      setPending(false);
    }
  };
  return (
    <>
      <PageHeader
        eyebrow="Commandes"
        title={existing ? "Modifier la commande" : "Nouvelle commande"}
        description="Saisissez les produits et quantités une seule fois. Les trois documents les réutiliseront."
      />
      <form onSubmit={submit} className="space-y-6 border bg-card p-5 shadow-sm sm:p-6">
        <div className="grid gap-4 md:grid-cols-2">
          <div className="space-y-2">
            <Label>Client actif</Label>
            <select
              required
              value={customerId}
              onChange={(e) => chooseCustomer(e.target.value)}
              className="h-10 w-full rounded-md border bg-background px-3"
            >
              <option value="">Sélectionner</option>
              {data.customers.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.company_name}
                </option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <Label>Date</Label>
            <Input type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
        </div>
        <div className="grid gap-4 md:grid-cols-2">
          <div className="space-y-2">
            <Label>Commande (PO)</Label>
            <Input value={po} onChange={(e) => setPo(e.target.value)} maxLength={200} />
          </div>
          <div className="space-y-2">
            <Label>Ville de destination</Label>
            <Input value={city} onChange={(e) => setCity(e.target.value)} maxLength={120} />
          </div>
        </div>
        <div className="space-y-2">
          <Label>Adresse de destination</Label>
          <Textarea value={address} onChange={(e) => setAddress(e.target.value)} maxLength={500} />
        </div>
        <section>
          <div className="mb-3 flex items-center justify-between">
            <div>
              <h2 className="font-bold">Produits</h2>
              <p className="text-xs text-muted-foreground">Description et quantité commandée</p>
            </div>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() =>
                setLines((x) => [
                  ...x,
                  { key: Math.max(...x.map((l) => l.key)) + 1, description: "", quantity: "1" },
                ])
              }
            >
              <Plus /> Ajouter
            </Button>
          </div>
          <div className="space-y-3">
            {lines.map((line, index) => (
              <div
                key={line.key}
                className="grid gap-3 border bg-background p-3 md:grid-cols-[1fr_160px_auto] md:items-end"
              >
                <div className="space-y-2">
                  <Label>Description {index + 1}</Label>
                  <Input
                    required
                    value={line.description}
                    onChange={(e) => updateLine(line.key, "description", e.target.value)}
                  />
                </div>
                <div className="space-y-2">
                  <Label>Quantité</Label>
                  <Input
                    required
                    type="number"
                    min="0.001"
                    step="0.001"
                    value={line.quantity}
                    onChange={(e) => updateLine(line.key, "quantity", e.target.value)}
                  />
                </div>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  disabled={lines.length === 1}
                  onClick={() => setLines((x) => x.filter((l) => l.key !== line.key))}
                >
                  <Minus />
                </Button>
              </div>
            ))}
          </div>
        </section>
        {error && (
          <p role="alert" className="text-sm font-semibold text-danger">
            {error}
          </p>
        )}
        <div className="flex justify-end">
          <Button size="lg" disabled={pending}>
            {pending
              ? "Enregistrement…"
              : existing
                ? "Mettre à jour le brouillon"
                : "Enregistrer le brouillon"}
          </Button>
        </div>
      </form>
    </>
  );
}
