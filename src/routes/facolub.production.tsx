import { Outlet, createFileRoute } from "@tanstack/react-router";
export const Route = createFileRoute("/facolub/production")({
  head: () => ({
    meta: [
      { title: "Production — FACOLUB" },
      { name: "description", content: "Production workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Production — FACOLUB" },
      {
        property: "og:description",
        content: "Production workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Outlet,
});
