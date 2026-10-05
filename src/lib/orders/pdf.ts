import type { PDFFont, PDFImage, PDFPage } from "pdf-lib";

import type { DeliveryNoteDocument, TransportNoteDocument } from "./types";

const W = 595.28;
const H = 841.89;

type PdfKind = "delivery" | "transport";
type PdfDocument = DeliveryNoteDocument | TransportNoteDocument;
type Rgb = typeof import("pdf-lib").rgb;

const layout = {
  delivery: {
    tableX: 36,
    tableTop: 622,
    tableWidth: 504,
    tableHeaderHeight: 30,
    rowHeight: 29,
    minimumRowBottom: 215,
    bodySize: 9.5,
    lineThickness: 1.2,
    pageNumberY: 198,
  },
  transport: {
    tableX: 51,
    tableTop: 542,
    tableWidth: 479,
    tableHeaderHeight: 29,
    rowHeight: 25,
    minimumRowBottom: 188,
    bodySize: 9,
    lineThickness: 0.8,
    pageNumberY: 161,
  },
} as const;

function safe(value: string | null | undefined) {
  return (value || "-")
    .replace(/[–—]/g, "-")
    .replace(/[’]/g, "'")
    .split("")
    .filter((character) => character.charCodeAt(0) <= 255)
    .join("");
}

function date(value: string | null) {
  return value
    ? new Intl.DateTimeFormat("fr-FR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`))
    : "-";
}

function quantity(value: string) {
  return new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 3 }).format(Number(value));
}

function wrap(text: string, font: PDFFont, size: number, width: number) {
  const words = safe(text).split(/\s+/);
  const lines: string[] = [];
  let line = "";
  for (const word of words) {
    const candidate = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(candidate, size) <= width) {
      line = candidate;
    } else {
      if (line) lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines.length ? lines : [""];
}

async function logo(pdf: import("pdf-lib").PDFDocument) {
  try {
    const response = await fetch("/soma-invoice-logo.png");
    return response.ok ? pdf.embedPng(await response.arrayBuffer()) : null;
  } catch {
    return null;
  }
}

function right(page: PDFPage, text: string, x: number, y: number, font: PDFFont, size: number) {
  const value = safe(text);
  page.drawText(value, { x: x - font.widthOfTextAtSize(value, size), y, font, size });
}

function centered(
  page: PDFPage,
  text: string,
  centerX: number,
  y: number,
  font: PDFFont,
  size: number,
) {
  const value = safe(text);
  page.drawText(value, {
    x: centerX - font.widthOfTextAtSize(value, size) / 2,
    y,
    font,
    size,
  });
}

function fittedSize(text: string, font: PDFFont, preferred: number, width: number, minimum = 6.5) {
  const value = safe(text);
  let size = preferred;
  while (size > minimum && font.widthOfTextAtSize(value, size) > width) size -= 0.25;
  return size;
}

function fittedText(
  page: PDFPage,
  text: string,
  x: number,
  y: number,
  width: number,
  font: PDFFont,
  preferredSize: number,
  minimumSize = 6.5,
) {
  const value = safe(text);
  page.drawText(value, {
    x,
    y,
    font,
    size: fittedSize(value, font, preferredSize, width, minimumSize),
  });
}

function inline(
  page: PDFPage,
  name: string,
  value: string | null,
  x: number,
  y: number,
  font: PDFFont,
  bold: PDFFont,
  size = 9,
  gap = 4,
) {
  const label = safe(name);
  page.drawText(label, { x, y, font: bold, size });
  page.drawText(safe(value), {
    x: x + bold.widthOfTextAtSize(label, size) + gap,
    y,
    font,
    size,
  });
}

function drawLogo(
  page: PDFPage,
  image: PDFImage | null,
  x: number,
  y: number,
  width: number,
  bold: PDFFont,
) {
  if (image) {
    const scaled = image.scale(width / image.width);
    page.drawImage(image, { x, y, width: scaled.width, height: scaled.height });
    return;
  }
  page.drawText("SOMA LUBRIFIANTS", { x: x + 6, y: y + 15, font: bold, size: 20 });
}

function drawSeller(
  page: PDFPage,
  kind: PdfKind,
  image: PDFImage | null,
  font: PDFFont,
  bold: PDFFont,
) {
  if (kind === "delivery") {
    drawLogo(page, image, 33, 735, 205, bold);
    page.drawText("Vendeur:", { x: 50, y: 712, font: bold, size: 10 });
    page.drawText("Soma Lubrifiants", { x: 50, y: 697, font: bold, size: 10.5 });
    inline(page, "Ville :", "CASABLANCA", 50, 682, font, bold, 9.5, 3);
    inline(page, "Numéro de téléphone :", "+212 6 61 92 43 10", 50, 667, font, bold, 9.5, 3);
    inline(page, "WhatsApp:", "+212 6 08 93 11 12", 50, 652, font, bold, 9.5, 3);
    inline(page, "Email:", "contact@somalubrifiants.com", 50, 637, font, bold, 9.5, 3);
    return;
  }

  drawLogo(page, image, 63, 718, 220, bold);
  page.drawText("Vendeur:", { x: 57, y: 692, font: bold, size: 10 });
  page.drawText("Soma Lubrifiants", { x: 57, y: 676, font: bold, size: 10.5 });
  inline(page, "Ville :", "CASABLANCA", 57, 661, font, bold, 9.5, 3);
  inline(page, "Téléphone :", "+212 6 61 92 43 10", 57, 646, font, bold, 9.5, 3);
  inline(page, "WhatsApp :", "+212 6 08 93 11 12", 57, 631, font, bold, 9.5, 3);
  inline(page, "Email :", "contact@somalubrifiants.com", 57, 616, font, bold, 9.5, 3);
}

function drawDeliveryHeader(
  page: PDFPage,
  document: DeliveryNoteDocument,
  image: PDFImage | null,
  font: PDFFont,
  bold: PDFFont,
  rgb: Rgb,
) {
  drawSeller(page, "delivery", image, font, bold);

  page.drawRectangle({
    x: 382,
    y: 741,
    width: 158,
    height: 50,
    borderColor: rgb(0.25, 0.25, 0.25),
    borderWidth: 0.8,
  });
  inline(page, "DATE :", date(document.delivery_date), 392, 772, bold, bold, 8.6, 21);
  inline(page, "BON DE LIVRAISON :", document.delivery_note_number, 392, 752, bold, bold, 8.2, 2);

  page.drawRectangle({
    x: 276,
    y: 634,
    width: 264,
    height: 89,
    borderColor: rgb(0.25, 0.25, 0.25),
    borderWidth: 0.8,
  });
  page.drawText("Préparé pour:", { x: 288, y: 700, font: bold, size: 12 });
  fittedText(page, safe(document.prepared_for), 288, 675, 238, bold, 11.5, 8);
  inline(page, "Objet :", document.object, 288, 653, font, font, 8.5, 3);
  inline(page, "Date de remise :", date(document.handover_date), 288, 638, font, font, 8.5, 3);
}

function transportField(
  page: PDFPage,
  name: string,
  value: string | null,
  y: number,
  font: PDFFont,
  bold: PDFFont,
  rgb: Rgb,
) {
  const x = 286;
  const size = 8.7;
  const label = safe(name);
  page.drawText(label, { x, y, font: bold, size });
  const valueX = x + bold.widthOfTextAtSize(label, size) + 8;
  if (value?.trim()) {
    fittedText(page, value, valueX, y, 515 - valueX, font, size, 6.5);
  } else {
    page.drawLine({
      start: { x: valueX, y: y - 1 },
      end: { x: 515, y: y - 1 },
      thickness: 0.7,
      color: rgb(0.1, 0.1, 0.1),
    });
  }
}

function drawTransportHeader(
  page: PDFPage,
  document: TransportNoteDocument,
  image: PDFImage | null,
  font: PDFFont,
  bold: PDFFont,
  rgb: Rgb,
) {
  drawSeller(page, "transport", image, font, bold);

  page.drawRectangle({
    x: 357,
    y: 708,
    width: 174,
    height: 83,
    borderColor: rgb(0.18, 0.18, 0.18),
    borderWidth: 0.8,
  });
  inline(page, "DATE :", date(document.transport_date), 372, 769, bold, bold, 9.2, 42);
  centered(page, "BON DE TRANSPORT", 444, 744, bold, 9.5);
  centered(page, `N° ${safe(document.transport_note_number)}`, 444, 724, font, 8.8);

  page.drawRectangle({
    x: 272,
    y: 555,
    width: 259,
    height: 145,
    borderColor: rgb(0.18, 0.18, 0.18),
    borderWidth: 0.8,
  });
  page.drawText("Personne chargée du transport :", { x: 286, y: 678, font: bold, size: 10.5 });
  fittedText(page, safe(document.transport_person), 286, 658, 229, bold, 11.5, 8);
  transportField(page, "Expéditeur :", document.sender, 632, font, bold, rgb);
  transportField(page, "Prise en charge :", date(document.pickup_date), 615, font, bold, rgb);
  transportField(page, "Chargement :", document.loading_location, 598, font, bold, rgb);
  transportField(page, "Destination :", document.destination, 581, font, bold, rgb);
  transportField(page, "Véhicule / immat. :", document.vehicle_registration, 564, font, bold, rgb);
}

function drawHeader(
  page: PDFPage,
  kind: PdfKind,
  document: PdfDocument,
  image: PDFImage | null,
  font: PDFFont,
  bold: PDFFont,
  rgb: Rgb,
) {
  if (kind === "delivery") {
    drawDeliveryHeader(page, document as DeliveryNoteDocument, image, font, bold, rgb);
  } else {
    drawTransportHeader(page, document as TransportNoteDocument, image, font, bold, rgb);
  }
}

function drawTableHeader(page: PDFPage, kind: PdfKind, bold: PDFFont, rgb: Rgb) {
  const current = layout[kind];
  page.drawRectangle({
    x: current.tableX,
    y: current.tableTop - current.tableHeaderHeight,
    width: current.tableWidth,
    height: current.tableHeaderHeight,
    color: rgb(0.16, 0.16, 0.16),
  });
  const baseline = current.tableTop - current.tableHeaderHeight + 11;
  page.drawText("DESCRIPTION", {
    x: current.tableX + 13,
    y: baseline,
    font: bold,
    size: 9.5,
    color: rgb(1, 1, 1),
  });
  const quantityHeader = "QTE";
  const quantityCenter = current.tableX + current.tableWidth - 42;
  page.drawText(quantityHeader, {
    x: quantityCenter - bold.widthOfTextAtSize(quantityHeader, 9.5) / 2,
    y: baseline,
    font: bold,
    size: 9.5,
    color: rgb(1, 1, 1),
  });
  return current.tableTop - current.tableHeaderHeight;
}

function drawRow(
  page: PDFPage,
  kind: PdfKind,
  description: string,
  itemQuantity: string,
  y: number,
  height: number,
  lines: string[],
  bold: PDFFont,
  rgb: Rgb,
) {
  const current = layout[kind];
  const color = kind === "delivery" ? rgb(0.26, 0.26, 0.26) : rgb(0.04, 0.04, 0.04);
  const lineHeight = kind === "delivery" ? 10.5 : 10;
  const firstBaseline = lines.length === 1 ? y - (kind === "delivery" ? 18 : 16) : y - 12;
  lines.forEach((line, index) => {
    page.drawText(safe(line), {
      x: current.tableX + (kind === "delivery" ? 7 : 8),
      y: firstBaseline - index * lineHeight,
      font: bold,
      size: current.bodySize,
      color,
    });
  });
  right(
    page,
    quantity(itemQuantity),
    current.tableX + current.tableWidth - 12,
    firstBaseline,
    bold,
    kind === "delivery" ? 10 : 9.5,
  );
  page.drawLine({
    start: { x: current.tableX, y: y - height },
    end: { x: current.tableX + current.tableWidth, y: y - height },
    thickness: current.lineThickness,
    color: rgb(0.12, 0.12, 0.12),
  });
}

function drawLegalFooter(
  page: PDFPage,
  kind: PdfKind,
  document: PdfDocument,
  font: PDFFont,
  bold: PDFFont,
  rgb: Rgb,
  pageNumber: number,
  totalPages: number,
) {
  const current = layout[kind];
  right(
    page,
    `PAGE ${pageNumber} / ${totalPages}`,
    current.tableX + current.tableWidth,
    current.pageNumberY,
    bold,
    8,
  );

  if (kind === "delivery") {
    const delivery = document as DeliveryNoteDocument;
    page.drawRectangle({
      x: 36,
      y: 107,
      width: 504,
      height: 70,
      borderColor: rgb(0.72, 0.72, 0.72),
      borderWidth: 0.65,
    });
    page.drawText(
      "Marchandises remises pour acheminement selon les quantites indiquees ci-dessus.",
      {
        x: 48,
        y: 159,
        font,
        size: 8,
        color: rgb(0.24, 0.24, 0.24),
      },
    );
    page.drawText("Remis par SOMA LUBRIFIANTS", { x: 48, y: 120, font, size: 8 });
    fittedText(
      page,
      `Transport / reception : ${safe(delivery.transport_reception_name)}`,
      334,
      120,
      194,
      font,
      8,
      6.5,
    );
    centered(
      page,
      "SOMA LUBRIFIANTS S.A.R.L. - Siège social : RES PRIMA OFFICE 105AP ETG3 CASABLANCA -",
      W / 2,
      59,
      bold,
      fittedSize(
        "SOMA LUBRIFIANTS S.A.R.L. - Siège social : RES PRIMA OFFICE 105AP ETG3 CASABLANCA -",
        bold,
        10,
        W - 50,
        8,
      ),
    );
    centered(page, "Tél : 0661924310 / 0662622485 - ICE 002894269000071", W / 2, 43, bold, 9.5);
    return;
  }

  const transport = document as TransportNoteDocument;
  page.drawRectangle({
    x: 51,
    y: 73,
    width: 479,
    height: 71,
    borderColor: rgb(0.72, 0.72, 0.72),
    borderWidth: 0.65,
  });
  page.drawText(
    "Document d'accompagnement des marchandises - ne constitue ni facture ni preuve de paiement.",
    { x: 65, y: 123, font, size: 7.7 },
  );
  page.drawText("Remise : SOMA LUBRIFIANTS", { x: 65, y: 93, font, size: 7.7 });
  fittedText(
    page,
    `Prise en charge : ${safe(transport.transport_person)}`,
    405,
    93,
    111,
    font,
    7.7,
    6.2,
  );
  centered(
    page,
    "SOMA LUBRIFIANTS S.A.R.L. - Siège social : RES PRIMA OFFICE 105AP ETG3 CASABLANCA",
    W / 2,
    38,
    bold,
    fittedSize(
      "SOMA LUBRIFIANTS S.A.R.L. - Siège social : RES PRIMA OFFICE 105AP ETG3 CASABLANCA",
      bold,
      9.2,
      W - 70,
      7.5,
    ),
  );
  centered(page, "Tél : 0661924310 / 0662622485", W / 2, 22, bold, 9);
}

async function create(kind: PdfKind, document: PdfDocument) {
  const { PDFDocument, StandardFonts, rgb } = await import("pdf-lib");
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const image = await logo(pdf);
  const pages: PDFPage[] = [];
  const current = layout[kind];

  const addPage = () => {
    const page = pdf.addPage([W, H]);
    pages.push(page);
    drawHeader(page, kind, document, image, font, bold, rgb);
    return { page, y: drawTableHeader(page, kind, bold, rgb) };
  };

  let { page, y } = addPage();
  for (const item of document.items) {
    const lines = wrap(item.description, bold, current.bodySize, current.tableWidth - 90);
    const lineHeight = kind === "delivery" ? 10.5 : 10;
    const height = Math.max(current.rowHeight, lines.length * lineHeight + 10);
    if (y - height < current.minimumRowBottom) {
      ({ page, y } = addPage());
    }
    drawRow(page, kind, item.description, item.quantity, y, height, lines, bold, rgb);
    y -= height;
  }

  pages.forEach((pdfPage, index) =>
    drawLegalFooter(pdfPage, kind, document, font, bold, rgb, index + 1, pages.length),
  );

  const number =
    kind === "delivery"
      ? (document as DeliveryNoteDocument).delivery_note_number
      : (document as TransportNoteDocument).transport_note_number;
  pdf.setTitle(number ?? (kind === "delivery" ? "Bon de livraison" : "Bon de transport"));
  pdf.setAuthor("SOMA Lubrifiants");
  pdf.setCreator("SOMA Lubrifiants");
  const bytes = await pdf.save();
  return new Blob(
    [bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer],
    { type: "application/pdf" },
  );
}

export const createDeliveryNotePdfBlob = (document: DeliveryNoteDocument) =>
  create("delivery", document);

export const createTransportNotePdfBlob = (document: TransportNoteDocument) =>
  create("transport", document);

export function documentFilename(document: PdfDocument, kind: PdfKind) {
  const number =
    kind === "delivery"
      ? (document as DeliveryNoteDocument).delivery_note_number
      : (document as TransportNoteDocument).transport_note_number;
  return `${number ?? `BROUILLON-${document.id.slice(0, 8)}`}.pdf`;
}

export async function previewDocumentPdf(document: PdfDocument, kind: PdfKind) {
  const preview = window.open("about:blank", "_blank");
  const blob = await create(kind, document);
  const url = URL.createObjectURL(blob);
  if (preview) {
    preview.opener = null;
    preview.location.replace(url);
  } else {
    window.location.assign(url);
  }
  window.setTimeout(() => URL.revokeObjectURL(url), 300000);
}

export async function downloadDocumentPdf(document: PdfDocument, kind: PdfKind) {
  const blob = await create(kind, document);
  const url = URL.createObjectURL(blob);
  const anchor = window.document.createElement("a");
  anchor.href = url;
  anchor.download = documentFilename(document, kind);
  anchor.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
}
