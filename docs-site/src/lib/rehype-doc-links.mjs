import path from 'node:path'

function walk(node, visit) {
  if (!node || typeof node !== 'object') return
  visit(node)
  if (Array.isArray(node.children)) {
    for (const child of node.children) walk(child, visit)
  }
}

export default function rehypeDocLinks() {
  return (tree, file) => {
    const sourcePath = String(file.path ?? '').replaceAll('\\', '/')
    const docsMarker = '/docs/'
    const markerIndex = sourcePath.lastIndexOf(docsMarker)
    const sourceDoc = markerIndex === -1 ? '' : sourcePath.slice(markerIndex + docsMarker.length)
    const sourceDirectory = path.posix.dirname(sourceDoc)

    walk(tree, (node) => {
      if (node.type !== 'element' || node.tagName !== 'a') return
      const href = node.properties?.href
      if (typeof href !== 'string' || !href.match(/\.md(?:#.*)?$/)) return

      const [relativePath, hash] = href.split('#', 2)
      const resolved = path.posix.normalize(path.posix.join(sourceDirectory, relativePath))
      node.properties.href = `/docs/${resolved.replace(/\.md$/, '')}${hash ? `#${hash}` : ''}`
    })
  }
}
