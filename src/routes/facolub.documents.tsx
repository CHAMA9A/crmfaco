import { createFileRoute } from "@tanstack/react-router";
import { InvoiceWorkspace } from "@/components/invoices/invoice-workspace";
import { getInvoiceWorkspaceFn } from "@/lib/invoices/functions";

export const Route = createFileRoute("/facolub/documents")({
  loader: () => getInvoiceWorkspaceFn(),
  head: () => ({
    meta: [
      { title: "Documents — FACOLUB" },
      { name: "description", content: "Documents workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Documents — FACOLUB" },
      {
        property: "og:description",
        content: "Documents workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: DocumentsRoute,
});

function DocumentsRoute() {
  return <InvoiceWorkspace data={Route.useLoaderData()} />;
}
