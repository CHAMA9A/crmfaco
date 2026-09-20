import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/prices")({
  head: () => ({
    meta: [
      { title: "Prices — FACOLUB" },
      { name: "description", content: "Prices workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Prices — FACOLUB" },
      { property: "og:description", content: "Prices workspace for FACOLUB internal operations." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="prices" />,
});
