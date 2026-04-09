# n8n Hugging Face Space

This repository contains the Docker configuration for running n8n on Hugging Face Spaces with integrated services (Ollama, Qdrant, PostgreSQL).

## Environment Variables

The following environment variables are configured for OAuth integration with ClickUp via Vercel proxy:

- `N8N_URL=https://n8n-clickup-oauth-proxy.vercel.app/`
- `N8N_HOST=n8n-clickup-oauth-proxy.vercel.app`
- `N8N_PROTOCOL=https`
- `N8N_EDITOR_BASE_URL=https://n8n-clickup-oauth-proxy.vercel.app/`
- `WEBHOOK_URL=https://n8n-clickup-oauth-proxy.vercel.app/`
- `N8N_TRUST_PROXY=true`

## OAuth Configuration

To use ClickUp OAuth with this n8n instance:

1. Create a new ClickUp OAuth credential in n8n
2. Set the redirect URL to: `https://n8n-clickup-oauth-proxy.vercel.app/`
3. In ClickUp's Developer Console, configure the OAuth redirect URI to: `https://n8n-clickup-oauth-proxy.vercel.app/`
4. The Vercel proxy will forward the OAuth callback to this n8n instance

## Vercel Proxy

The OAuth proxy repository: https://github.com/Greene-ctrl/n8n-clickup-oauth-proxy
