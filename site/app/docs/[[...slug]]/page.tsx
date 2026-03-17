import type { Metadata } from "next";
import DocsClientPage from "./client";
import { getDocPages, getDocsNavigation, getPageContent, getPageId, getSerializedDocs } from "../../../lib/docs";

export const dynamicParams = false;

export function generateStaticParams() {
  return [
    { slug: [] },
    ...getDocPages().map((page) => ({ slug: [page.id] })),
  ];
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug?: string[] }>;
}): Promise<Metadata> {
  const resolved = await params;
  const pageId = getPageId(resolved.slug);
  const page = getPageContent(pageId);
  const isDocsHome = !resolved.slug || resolved.slug.length === 0;
  const imagePath = isDocsHome ? "/og/docs.png" : `/og/docs/${page.id}.png`;
  const title = isDocsHome ? "Vox Docs" : `${page.title} · Vox Docs`;
  const description = isDocsHome
    ? "Documentation for the Vox local transcription runtime."
    : `${page.title} documentation for the Vox local transcription runtime.`;

  return {
    title,
    description,
    openGraph: {
      title,
      description,
      images: [{ url: imagePath }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: [imagePath],
    },
  };
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
