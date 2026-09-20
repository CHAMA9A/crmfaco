import { createFileRoute } from "@tanstack/react-router";
import { PlaceholderPage } from "@/components/app/pages";
export const Route = createFileRoute("/facolub/receiving")({
  head: () => ({
    meta: [
      { title: "Receiving — FACOLUB" },
      { name: "description", content: "Receiving workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Receiving — FACOLUB" },
      {
        property: "og:description",
        content: "Receiving workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <PlaceholderPage module="receiving" />,
});
