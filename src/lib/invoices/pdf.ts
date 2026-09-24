import type { PDFFont, PDFImage, PDFPage } from "pdf-lib";

import { formatMad } from "./money";
import type { InvoiceDocument } from "./types";

type PreviewWindow = Window | null;

const A4_WIDTH = 595.28;
const A4_HEIGHT = 841.89;
const PAGE_MARGIN = 36;

function pdfText(value: string | null | undefined) {
  const normalized = (value || "—")
    .replace(/œ/g, "oe")
    .replace(/Œ/g, "OE")
    .replace(/[–—]/g, "-")
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"');
  return Array.from(normalized)
    .filter((character) => character.charCodeAt(0) <= 0xff)
    .join("");
}

function formatInvoiceDate(value: string) {
  return new Intl.DateTimeFormat("fr-FR", { dateStyle: "short", timeZone: "UTC" }).format(
    new Date(`${value}T00:00:00Z`),
  );
}

function formatQuantity(value: string) {
  return new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 3 }).format(Number(value));
}

function splitText(text: string, font: PDFFont, size: number, maxWidth: number) {
  const words = pdfText(text)
    .split(/\s+/)
    .filter(Boolean)
    .flatMap((word) => {
      if (font.widthOfTextAtSize(word, size) <= maxWidth) return [word];
      const chunks: string[] = [];
      let chunk = "";
      for (const character of word) {
        const candidate = `${chunk}${character}`;
        if (chunk && font.widthOfTextAtSize(candidate, size) > maxWidth) {
          chunks.push(chunk);
          chunk = character;
        } else {
          chunk = candidate;
        }
      }
      if (chunk) chunks.push(chunk);
      return chunks;
    });
  if (words.length === 0) return [""];

  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
      current = candidate;
      continue;
    }
    if (current) lines.push(current);
    current = word;
  }
  if (current) lines.push(current);
  return lines;
}

function drawRightText(
  page: PDFPage,
  text: string,
  right: number,
  y: number,
  font: PDFFont,
  size: number,
) {
  const safeText = pdfText(text);
  page.drawText(safeText, {
    x: right - font.widthOfTextAtSize(safeText, size),
    y,
    font,
    size,
  });
}

function drawLabelValue(
  page: PDFPage,
  label: string,
  value: string | null,
  x: number,
  y: number,
  labelWidth: number,
  font: PDFFont,
  bold: PDFFont,
) {
  page.drawText(pdfText(label), { x, y, size: 8.2, font: bold });
  page.drawText(pdfText(value), { x: x + labelWidth, y, size: 8.2, font });
}

function drawTableHeader(
  page: PDFPage,
  y: number,
  bold: PDFFont,
  rgb: typeof import("pdf-lib").rgb,
) {
  const x = PAGE_MARGIN;
  const widths = [286, 55, 90, 92] as const;
  const labels = ["DESCRIPTION", "QTÉ", "PRIX Unitaire", "TOTAL"];
  page.drawRectangle({ x, y: y - 24, width: 523, height: 24, color: rgb(0.08, 0.08, 0.08) });

  let cursor = x;
  labels.forEach((label, index) => {
    const labelWidth = bold.widthOfTextAtSize(label, 8.5);
    page.drawText(label, {
      x: index === 0 ? cursor + 8 : cursor + (widths[index]! - labelWidth) / 2,
      y: y - 16,
      size: 8.5,
      font: bold,
      color: rgb(1, 1, 1),
    });
    cursor += widths[index]!;
  });
  return y - 24;
}

function drawLegalFooter(
  page: PDFPage,
  font: PDFFont,
  bold: PDFFont,
  rgb: typeof import("pdf-lib").rgb,
) {
  const center = A4_WIDTH / 2;
  page.drawLine({
    start: { x: PAGE_MARGIN, y: 61 },
    end: { x: A4_WIDTH - PAGE_MARGIN, y: 61 },
    thickness: 0.7,
    color: rgb(0.3, 0.3, 0.3),
  });
  const lines = [
    ["TAXE PROFESSIONNELLE N° 11337/2021/48285", bold, 8],
    [
      "SOMA LUBRIFIANTS S.A.R.L. - Siège social : RES PRIMA OFFICE 105AP ETG3 CASABLANCA -",
      font,
      7.2,
    ],
    ["Tél : 0661924310 / 0662622485 - ICE : 002894269000071", font, 7.2],
  ] as const;
  lines.forEach(([text, selectedFont, size], index) => {
    const safeText = pdfText(text);
    page.drawText(safeText, {
      x: center - selectedFont.widthOfTextAtSize(safeText, size) / 2,
      y: 46 - index * 11,
      size,
      font: selectedFont,
      color: rgb(0.12, 0.12, 0.12),
    });
  });
}

async function loadLogo(pdfDocument: import("pdf-lib").PDFDocument) {
  try {
    const response = await fetch("/soma-invoice-logo.png");
    if (!response.ok) return null;
    return await pdfDocument.embedPng(await response.arrayBuffer());
  } catch {
    return null;
  }
}

function drawFirstPageHeader(
  page: PDFPage,
  invoice: InvoiceDocument,
  font: PDFFont,
  bold: PDFFont,
  logo: PDFImage | null,
  rgb: typeof import("pdf-lib").rgb,
) {
  if (logo) {
    const scaled = logo.scaleToFit(176, 58);
    page.drawImage(logo, { x: PAGE_MARGIN, y: 754, width: scaled.width, height: scaled.height });
  } else {
    page.drawText("SOMA", { x: PAGE_MARGIN, y: 777, size: 28, font: bold });
    page.drawText("LUBRIFIANTS", { x: PAGE_MARGIN + 2, y: 762, size: 9, font: bold });
  }

  page.drawText("Vendeur:", { x: PAGE_MARGIN, y: 738, size: 8.5, font: bold });
  page.drawText("Soma Lubrifiants", { x: PAGE_MARGIN, y: 723, size: 10, font: bold });
  drawLabelValue(page, "Ville :", "CASABLANCA", PAGE_MARGIN, 708, 36, font, bold);
  drawLabelValue(
    page,
    "Numéro de téléphone :",
    "+212 6 61 92 43 10",
    PAGE_MARGIN,
    695,
    101,
    font,
    bold,
  );
  drawLabelValue(page, "WhatsApp :", "+212 6 08 93 11 12", PAGE_MARGIN, 682, 55, font, bold);
  drawLabelValue(page, "Email :", "contact@somalubrifiants.com", PAGE_MARGIN, 669, 36, font, bold);

  const boxX = 348;
  const boxWidth = 211;
  page.drawRectangle({
    x: boxX,
    y: 752,
    width: boxWidth,
    height: 54,
    color: rgb(1, 1, 1),
    borderColor: rgb(0.08, 0.08, 0.08),
    borderWidth: 0.8,
  });
  page.drawLine({
    start: { x: boxX, y: 779 },
    end: { x: boxX + boxWidth, y: 779 },
    thickness: 0.6,
  });
  drawLabelValue(
    page,
    "DATE :",
    formatInvoiceDate(invoice.invoice_date),
    boxX + 9,
    788,
    73,
    font,
    bold,
  );
  drawLabelValue(
    page,
    "Facture :",
    invoice.invoice_number ?? "Brouillon",
    boxX + 9,
    761,
    73,
    font,
    bold,
  );

  const clientBoxX = 330;
  const clientBoxWidth = 229;
  page.drawRectangle({
    x: clientBoxX,
    y: 600,
    width: clientBoxWidth,
    height: 136,
    color: rgb(1, 1, 1),
    borderColor: rgb(0.08, 0.08, 0.08),
    borderWidth: 0.8,
  });
  const clientRows: Array<[string, string | null]> = [
    ["Client :", invoice.customer_name_snapshot],
    ["Commande (PO) :", invoice.purchase_order],
    ["VILLE :", invoice.customer_city_snapshot],
    ["Adresse :", invoice.customer_address_snapshot],
    ["ICE :", invoice.customer_ice_snapshot],
  ];
  let clientY = 716;
  clientRows.forEach(([label, value]) => {
    const valueLines = splitText(value || "—", font, 7.4, clientBoxWidth - 91);
    page.drawText(pdfText(label), { x: clientBoxX + 8, y: clientY, size: 7.4, font: bold });
    valueLines.forEach((line, index) => {
      page.drawText(line, {
        x: clientBoxX + 83,
        y: clientY - index * 9,
        size: 7.4,
        font,
      });
    });
    clientY -= Math.max(17, valueLines.length * 9 + 5);
  });

  page.drawText("FACTURE", {
    x: PAGE_MARGIN,
    y: 578,
    size: 17,
    font: bold,
    color: rgb(0.08, 0.08, 0.08),
  });
}

export async function createInvoicePdfBlob(invoice: InvoiceDocument) {
  const { PDFDocument, StandardFonts, rgb } = await import("pdf-lib");
  const pdfDocument = await PDFDocument.create();
  const font = await pdfDocument.embedFont(StandardFonts.Helvetica);
  const bold = await pdfDocument.embedFont(StandardFonts.HelveticaBold);
  const logo = await loadLogo(pdfDocument);
  const pages: PDFPage[] = [];

  let page = pdfDocument.addPage([A4_WIDTH, A4_HEIGHT]);
  pages.push(page);
  drawFirstPageHeader(page, invoice, font, bold, logo, rgb);
  let y = drawTableHeader(page, 555, bold, rgb);
  const widths = [286, 55, 90, 92] as const;

  for (const item of invoice.items) {
    const descriptionLines = splitText(item.description, font, 8.5, widths[0]! - 16);
    const rowHeight = Math.max(25, descriptionLines.length * 11 + 10);
    if (y - rowHeight < 112) {
      page = pdfDocument.addPage([A4_WIDTH, A4_HEIGHT]);
      pages.push(page);
      page.drawText(pdfText(invoice.invoice_number ?? "Facture brouillon"), {
        x: PAGE_MARGIN,
        y: 790,
        size: 9,
        font: bold,
      });
      y = drawTableHeader(page, 770, bold, rgb);
    }

    page.drawRectangle({
      x: PAGE_MARGIN,
      y: y - rowHeight,
      width: 523,
      height: rowHeight,
      borderWidth: 0.45,
      borderColor: rgb(0.55, 0.55, 0.55),
    });
    let columnX = PAGE_MARGIN;
    for (let index = 1; index < widths.length; index += 1) {
      columnX += widths[index - 1]!;
      page.drawLine({
        start: { x: columnX, y },
        end: { x: columnX, y: y - rowHeight },
        thickness: 0.45,
        color: rgb(0.55, 0.55, 0.55),
      });
    }

    descriptionLines.forEach((line, index) => {
      page.drawText(line, { x: PAGE_MARGIN + 8, y: y - 16 - index * 11, size: 8.5, font });
    });
    drawRightText(page, formatQuantity(item.quantity), PAGE_MARGIN + 286 + 47, y - 16, font, 8.5);
    drawRightText(
      page,
      formatMad(item.unit_price).replace(" MAD", ""),
      PAGE_MARGIN + 431 - 8,
      y - 16,
      font,
      8.5,
    );
    drawRightText(
      page,
      formatMad(item.line_total).replace(" MAD", ""),
      PAGE_MARGIN + 523 - 8,
      y - 16,
      bold,
      8.5,
    );
    y -= rowHeight;
  }

  if (y - 52 < 90) {
    page = pdfDocument.addPage([A4_WIDTH, A4_HEIGHT]);
    pages.push(page);
    y = 770;
  }

  const totalWidth = 237;
  const totalX = A4_WIDTH - PAGE_MARGIN - totalWidth;
  page.drawRectangle({
    x: totalX,
    y: y - 42,
    width: totalWidth,
    height: 42,
    borderWidth: 1.1,
    borderColor: rgb(0.08, 0.08, 0.08),
  });
  page.drawText("TOTAL :", { x: totalX + 13, y: y - 26, size: 11, font: bold });
  drawRightText(
    page,
    formatMad(invoice.authoritative_total),
    totalX + totalWidth - 13,
    y - 26,
    bold,
    11,
  );
  drawLegalFooter(page, font, bold, rgb);

  pages.forEach((pdfPage, index) => {
    if (pages.length > 1) {
      const label = `${index + 1} / ${pages.length}`;
      drawRightText(pdfPage, label, A4_WIDTH - PAGE_MARGIN, 75, font, 7);
    }
  });

  pdfDocument.setTitle(invoice.invoice_number ?? "Facture SOMA Lubrifiants");
  pdfDocument.setAuthor("SOMA Lubrifiants");
  pdfDocument.setSubject("Facture commerciale");
  const bytes = await pdfDocument.save();
  const buffer = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
  return new Blob([buffer], { type: "application/pdf" });
}

export function invoicePdfFilename(invoice: InvoiceDocument) {
  const base = invoice.invoice_number ?? `BROUILLON-${invoice.id.slice(0, 8)}`;
  return `${base.replace(/[^a-zA-Z0-9._-]+/g, "-")}.pdf`;
}

export function reserveInvoicePdfPreview(): PreviewWindow {
  const preview = window.open("about:blank", "_blank");
  if (preview) {
    preview.opener = null;
    preview.document.title = "Préparation du PDF…";
    preview.document.body.innerHTML =
      '<p style="font:16px system-ui;padding:24px">Préparation du PDF SOMA…</p>';
  }
  return preview;
}

export async function previewInvoicePdf(invoice: InvoiceDocument, preview: PreviewWindow) {
  const blob = await createInvoicePdfBlob(invoice);
  const url = URL.createObjectURL(blob);
  if (preview && !preview.closed) preview.location.replace(url);
  else window.location.assign(url);
  window.setTimeout(() => URL.revokeObjectURL(url), 300_000);
}

export async function downloadInvoicePdf(invoice: InvoiceDocument) {
  const blob = await createInvoicePdfBlob(invoice);
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = invoicePdfFilename(invoice);
  anchor.style.display = "none";
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
