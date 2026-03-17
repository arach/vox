import DocsClientPage from "./client";
import { getDocPages, getDocsNavigation, getPageContent, getPageId, getSerializedDocs } from "../../../lib/docs";

export const dynamicParams = false;

export function generateStaticParams() {
  return [
    { slug: [] },
    ...getDocPages().map((page) => ({ slug: [page.id] })),
  ];
}

export default async function DocsPage({
  params,
}: {
  params: Promise<{ slug?: string[] }>;
}) {
  const resolved = await params;
  const pageId = getPageId(resolved.slug);

  return (
    <DocsClientPage
      docs={getSerializedDocs()}
      navigation={getDocsNavigation()}
      initialPage={pageId}
      pageTitle={getPageContent(pageId).title}
    />
  );
}
