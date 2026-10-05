import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/documents")({
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
  component: DocumentsLayout,
});

function DocumentsLayout() {
  return <Outlet />;
}
