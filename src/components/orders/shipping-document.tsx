import { Download, Eye } from "lucide-react";
import { useServerFn } from "@tanstack/react-start";
import { useState, type FormEvent } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  issueDeliveryNoteFn,
  issueTransportNoteFn,
  updateDeliveryNoteFn,
  updateTransportNoteFn,
} from "@/lib/orders/functions";
import { downloadDocumentPdf, previewDocumentPdf } from "@/lib/orders/pdf";
import type { DeliveryNoteDocument, TransportNoteDocument } from "@/lib/orders/types";

type Props =
  | { kind: "delivery"; document: DeliveryNoteDocument; printable?: boolean }
  | { kind: "transport"; document: TransportNoteDocument; printable?: boolean };
const fieldClass = "space-y-2";

export function ShippingDocument(props: Props) {
  const updateDelivery = useServerFn(updateDeliveryNoteFn);
  const updateTransport = useServerFn(updateTransportNoteFn);
  const issueDelivery = useServerFn(issueDeliveryNoteFn);
  const issueTransport = useServerFn(issueTransportNoteFn);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const document = props.document as DeliveryNoteDocument & TransportNoteDocument;
  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setPending(true);
    setError("");
    const form = new FormData(event.currentTarget);
    try {
      if (props.kind === "delivery")
        await updateDelivery({
          data: {
            deliveryNoteId: document.id,
            deliveryDate: String(form.get("date")),
            preparedFor: String(form.get("preparedFor")),
            object: String(form.get("object")),
            handoverDate: String(form.get("handoverDate")),
            transportReceptionName: String(form.get("reception")),
          },
        });
      else
        await updateTransport({
          data: {
            transportNoteId: document.id,
            transportDate: String(form.get("date")),
            transportPerson: String(form.get("person")),
            sender: String(form.get("sender")),
            pickupDate: String(form.get("pickupDate")),
            loadingLocation: String(form.get("loading")),
            destination: String(form.get("destination")),
            vehicleRegistration: String(form.get("vehicle")),
          },
        });
      window.location.reload();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Enregistrement impossible");
      setPending(false);
    }
  };
  const issue = async () => {
    setPending(true);
    setError("");
    try {
      if (props.kind === "delivery") await issueDelivery({ data: { documentId: document.id } });
      else await issueTransport({ data: { documentId: document.id } });
      window.location.reload();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Émission impossible");
      setPending(false);
    }
  };
  return (
    <div className="space-y-5">
      {!props.printable && (
        <div className="flex flex-wrap justify-between gap-2">
          <Button asChild variant="outline">
            <a href={`/facolub/documents/orders/${document.order_id}`}>Retour commande</a>
          </Button>
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => void previewDocumentPdf(document, props.kind)}>
              <Eye /> Aperçu PDF
            </Button>
            <Button onClick={() => void downloadDocumentPdf(document, props.kind)}>
              <Download /> PDF
            </Button>
          </div>
        </div>
      )}
      {!props.printable && document.status === "draft" && (
        <form onSubmit={save} className="grid gap-4 border bg-card p-5 sm:grid-cols-2">
          <div className={fieldClass}>
            <Label>Date</Label>
            <Input
              name="date"
              type="date"
              required
              defaultValue={
                props.kind === "delivery"
                  ? (document.delivery_date ?? "")
                  : (document.transport_date ?? "")
              }
            />
          </div>
          {props.kind === "delivery" ? (
            <>
              <div className={fieldClass}>
                <Label>Préparé pour</Label>
                <Input name="preparedFor" required defaultValue={document.prepared_for ?? ""} />
              </div>
              <div className={fieldClass}>
                <Label>Objet</Label>
                <Input name="object" required defaultValue={document.object} />
              </div>
              <div className={fieldClass}>
                <Label>Date de remise</Label>
                <Input
                  name="handoverDate"
                  type="date"
                  required
                  defaultValue={document.handover_date ?? ""}
                />
              </div>
              <div className={fieldClass}>
                <Label>Transport / réception</Label>
                <Input name="reception" defaultValue={document.transport_reception_name ?? ""} />
              </div>
            </>
          ) : (
            <>
              <div className={fieldClass}>
                <Label>Personne chargée du transport</Label>
                <Input name="person" required defaultValue={document.transport_person ?? ""} />
              </div>
              <div className={fieldClass}>
                <Label>Expéditeur</Label>
                <Input name="sender" required defaultValue={document.sender} />
              </div>
              <div className={fieldClass}>
                <Label>Prise en charge</Label>
                <Input
                  name="pickupDate"
                  type="date"
                  required
                  defaultValue={document.pickup_date ?? ""}
                />
              </div>
              <div className={fieldClass}>
                <Label>Chargement</Label>
                <Input name="loading" required defaultValue={document.loading_location} />
              </div>
              <div className={fieldClass}>
                <Label>Destination</Label>
                <Input name="destination" required defaultValue={document.destination ?? ""} />
              </div>
              <div className={fieldClass}>
                <Label>Véhicule / immat.</Label>
                <Input name="vehicle" required defaultValue={document.vehicle_registration ?? ""} />
              </div>
            </>
          )}
          <div className="flex gap-2 sm:col-span-2 sm:justify-end">
            <Button type="submit" variant="outline" disabled={pending}>
              Enregistrer
            </Button>
            <Button type="button" disabled={pending} onClick={() => void issue()}>
              Émettre
            </Button>
          </div>
          {error && <p className="text-sm font-semibold text-danger sm:col-span-2">{error}</p>}
        </form>
      )}
      <article className="mx-auto min-h-[900px] max-w-[800px] bg-white p-10 text-black shadow">
        <header className="flex justify-between gap-8">
          <img src="/soma-invoice-logo.png" className="h-16 w-auto" />
          <div className="border p-4 text-sm">
            <p>
              <b>DATE :</b>{" "}
              {props.kind === "delivery" ? document.delivery_date : document.transport_date}
            </p>
            <p className="mt-2">
              <b>{props.kind === "delivery" ? "BON LIVRAISON" : "BON DE TRANSPORT"} :</b>{" "}
              {props.kind === "delivery"
                ? document.delivery_note_number
                : document.transport_note_number}
            </p>
          </div>
        </header>
        <h1 className="mt-12 text-xl font-black">
          {props.kind === "delivery" ? "BON DE LIVRAISON" : "BON DE TRANSPORT"}
        </h1>
        <table className="mt-5 w-full border-collapse text-sm">
          <thead className="bg-black text-white">
            <tr>
              <th className="p-3 text-left">DESCRIPTION</th>
              <th className="w-28 p-3 text-right">QTE</th>
            </tr>
          </thead>
          <tbody>
            {document.items.map((item) => (
              <tr key={item.id} className="border">
                <td className="p-3">{item.description}</td>
                <td className="p-3 text-right font-bold">{item.quantity}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </article>
    </div>
  );
}
