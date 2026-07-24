# mewmew API Worker

Cloudflare Worker for `POST /v1/parse`. It authenticates the app, applies a
per-token daily KV quota, calls DeepSeek, validates the JSON response, and
converts reminder times from the supplied IANA timezone to Unix seconds.

## Setup

Install dependencies:

```sh
npm install
```

Create the production KV namespace:

```sh
npx wrangler kv namespace create RATE_LIMIT
```

Copy the returned namespace ID and replace
`REPLACE_WITH_RATE_LIMIT_NAMESPACE_ID` in `wrangler.jsonc`.

Configure both secrets:

```sh
npx wrangler secret put APP_TOKEN
npx wrangler secret put DEEPSEEK_API_KEY
```

`DAILY_QUOTA` is optional and defaults to `200`. To override it, add a
`DAILY_QUOTA` string under `vars` in `wrangler.jsonc` or configure the
equivalent environment variable for the target Worker environment.

## Verify

```sh
npm test
npm run typecheck
```

Deployment is intentionally a separate, user-confirmed operation:

```sh
npx wrangler deploy
```
