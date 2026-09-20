import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/history")({
  head: () => ({
    meta: [
      { title: "History — FACOLUB" },
      { name: "description", content: "History workspace for FACOLUB internal operations." },
      { property: "og:title", content: "History — FACOLUB" },
      { property: "og:description", content: "History workspace for FACOLUB internal operations." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="history" />,
});
