import { Outlet, createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/facolub/customers")({
  head: () => ({
    meta: [
      { title: "Customers — FACOLUB" },
      { name: "description", content: "Customers workspace for FACOLUB internal operations." },
      { property: "og:title", content: "Customers — FACOLUB" },
      {
        property: "og:description",
        content: "Customers workspace for FACOLUB internal operations.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: () => <Outlet />,
});
