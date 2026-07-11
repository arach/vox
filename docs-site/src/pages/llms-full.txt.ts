import llmsFull from '../../../llms-full.txt?raw'

export function GET() {
  return new Response(llmsFull, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  })
}
