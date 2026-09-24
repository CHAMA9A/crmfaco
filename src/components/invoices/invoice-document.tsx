import { ArrowLeft, Download, Eye, Printer } from "lucide-react";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import { formatMad } from "@/lib/invoices/money";
import {
  downloadInvoicePdf,
  previewInvoicePdf,
  reserveInvoicePdfPreview,
} from "@/lib/invoices/pdf";
import type { InvoiceDocument as InvoiceDocumentData } from "@/lib/invoices/types";

function formatQuantity(value: string) {
  return new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 3 }).format(Number(value));
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeZone: "UTC" }).format(
    new Date(`${value}T00:00:00Z`),
  );
}

export function InvoiceDocument({
  invoice,
  printable = false,
}: {
  invoice: InvoiceDocumentData;
  printable?: boolean;
}) {
  const [pdfAction, setPdfAction] = useState<"preview" | "download" | null>(null);
  const [pdfError, setPdfError] = useState("");

  const printInvoice = () => {
    window.focus();
    window.setTimeout(() => window.print(), 50);
  };

  const previewPdf = async () => {
    if (pdfAction) return;
    const preview = reserveInvoicePdfPreview();
    setPdfAction("preview");
    setPdfError("");
    try {
      await previewInvoicePdf(invoice, preview);
    } catch {
      preview?.close();
      setPdfError("Impossible de générer l’aperçu PDF. Réessayez.");
    } finally {
      setPdfAction(null);
    }
  };

  const downloadPdf = async () => {
    if (pdfAction) return;
    setPdfAction("download");
    setPdfError("");
    try {
      await downloadInvoicePdf(invoice);
    } catch {
      setPdfError("Impossible de télécharger le PDF. Réessayez.");
    } finally {
      setPdfAction(null);
    }
  };

  return (
    <div className={printable ? "invoice-print-shell" : "space-y-5"}>
      <div className="invoice-screen-actions flex flex-wrap items-center justify-between gap-3">
        <Button variant="outline" asChild>
          <a href="/facolub/documents">
            <ArrowLeft />
            Documents
          </a>
        </Button>
        <div className="flex flex-wrap gap-2">
          {!printable && (
            <Button
              type="button"
              variant="outline"
              onClick={() => void previewPdf()}
              disabled={pdfAction !== null}
            >
              <Eye />
              {pdfAction === "preview" ? "Préparation…" : "Aperçu PDF"}
            </Button>
          )}
          <Button type="button" onClick={() => void downloadPdf()} disabled={pdfAction !== null}>
            <Download />
            {pdfAction === "download" ? "Téléchargement…" : "Télécharger PDF"}
          </Button>
          {printable && (
            <Button type="button" variant="outline" onClick={printInvoice}>
              <Printer />
              Imprimer
            </Button>
          )}
        </div>
      </div>

      {pdfError && (
        <p role="alert" className="invoice-screen-actions text-sm font-semibold text-danger">
          {pdfError}
        </p>
      )}

      <article className={`soma-invoice ${printable ? "soma-invoice-print" : ""}`}>
        <header className="soma-invoice-header">
          <div className="soma-identity-column">
            <img
              src="/soma-invoice-logo.png"
              alt="SOMA Lubrifiants"
              className="soma-invoice-logo"
            />
            <div className="soma-seller-copy">
              <p className="soma-seller-heading">Vendeur:</p>
              <p className="soma-seller-name">Soma Lubrifiants</p>
              <p>
                <strong>Ville :</strong> CASABLANCA
              </p>
              <p>
                <strong>Numéro de téléphone :</strong> +212 6 61 92 43 10
              </p>
              <p>
                <strong>WhatsApp :</strong> +212 6 08 93 11 12
              </p>
              <p>
                <strong>Email :</strong> contact@somalubrifiants.com
              </p>
            </div>
          </div>
          <div className="soma-customer-column">
            <dl className="soma-meta-box">
              <div>
                <dt>DATE :</dt>
                <dd>{formatDate(invoice.invoice_date)}</dd>
              </div>
              <div>
                <dt>Facture :</dt>
                <dd>{invoice.invoice_number ?? "Brouillon"}</dd>
              </div>
            </dl>

            <dl className="soma-client-box">
              <div>
                <dt>Client :</dt>
                <dd>{invoice.customer_name_snapshot}</dd>
              </div>
              <div>
                <dt>Commande (PO) :</dt>
                <dd>{invoice.purchase_order ?? "—"}</dd>
              </div>
              <div>
                <dt>VILLE :</dt>
                <dd>{invoice.customer_city_snapshot ?? "—"}</dd>
              </div>
              <div>
                <dt>Adresse :</dt>
                <dd>{invoice.customer_address_snapshot ?? "—"}</dd>
              </div>
              <div>
                <dt>ICE :</dt>
                <dd>{invoice.customer_ice_snapshot ?? "—"}</dd>
              </div>
            </dl>
          </div>
        </header>

        <table className="soma-lines-table">
          <thead>
            <tr>
              <th>DESCRIPTION</th>
              <th>QTÉ</th>
              <th>PRIX Unitaire</th>
              <th>TOTAL</th>
            </tr>
          </thead>
          <tbody>
            {invoice.items.map((item) => (
              <tr key={item.id}>
                <td>{item.description}</td>
                <td>{formatQuantity(item.quantity)}</td>
                <td>{formatMad(item.unit_price)}</td>
                <td>{formatMad(item.line_total)}</td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="soma-final-total" aria-label="Total de la facture">
          <span>TOTAL :</span>
          <strong>{formatMad(invoice.authoritative_total)}</strong>
        </div>

        <footer className="soma-invoice-footer">
          <p>
            <span className="soma-tax-label">TAXE PROFESSIONNELLE N° 11337/2021/48285</span>
          </p>
          <p className="soma-legal-line">
            SOMA LUBRIFIANTS S.A.R.L. - Siège social : RES PRIMA OFFICE 105AP ETG3 CASABLANCA -
          </p>
          <p className="soma-legal-line">Tél : 0661924310 / 0662622485 - ICE : 002894269000071</p>
        </footer>
      </article>
    </div>
  );
}
