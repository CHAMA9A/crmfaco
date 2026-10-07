import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/stock")({
  head: () => ({
    meta: [
      { title: "Stock — FACOLUB" },
      { name: "description", content: "Stock workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Stock — FACOLUB" },
      { property: "og:description", content: "Stock workspace for FACOLUB internal operations." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <Outlet />,
});
