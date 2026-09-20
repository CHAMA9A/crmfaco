import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/purchases")({
  head: () => ({
    meta: [
      { title: "Purchases — FACOLUB" },
      { name: "description", content: "Purchases workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Purchases — FACOLUB" },
      {
        property: "og:description",
        content: "Purchases workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="purchases" />,
});
