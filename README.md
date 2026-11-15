<p align="center">
<img width="2508" height="627" alt="image" src="https://github.com/user-attachments/assets/5b1a1a83-3f3e-4acd-b09f-00f87a1b7ae4" />
</p>

### Description

A Rails API that runs Google searches through SerpApi on demand and stores up to 10 organic results per search in SQLite.

### Installation

Prerequisites: 
- Ruby 3.4.12
- Bundler
- SQLite

From the project directory:

```sh
bundle install
cp .env.example .env
```

Edit `.env` and set your SerpApi key:

```env
SERPAPI_API_KEY=<your-serpapi-key>
```

Prepare the database:

```sh
bin/rails db:prepare
```

> Keep the app local. It has no authentication or rate limiting; exposing it publicly with a configured key lets others trigger SerpApi requests.

### Quick Start

Start the server:

```sh
bin/dev
```

Create a search:

```sh
curl -X POST http://localhost:3000/searches \
  -H 'Content-Type: application/json' \
  -d '{"search":{"query":"ruby on rails"}}'
```
or `POST` in `http://localhost:3000/searches`:

```json
{
  "search": {
    "query": "What does Gauss’s law for magnetism say?",
    "location": "São Paulo, Brazil",
    "hl": "pt"
  }
}
```

> You can also import the Insomnia workspace from [`insomnia.json`](insomnia.json).

### API Endpoints

| Method | Path | Behavior |
| --- | --- | --- |
| `GET` | `/health` | Returns API health. |
| `GET` | `/searches` | Lists saved searches, newest first. |
| `POST` | `/searches` | Runs a search and saves the response; returns `201` on success. |
| `GET` | `/searches/:id` | Returns a saved search. |
| `DELETE` | `/searches/:id` | Deletes a saved search; returns `204`. |

`POST /searches` requires `query` and accepts optional `location` and `hl` fields. `location` biases results toward a place. `hl` sets Google's interface language; it does not filter results by document language. Each search stores up to 10 organic results. `POST` waits for SerpApi; `GET` and `DELETE` operate on stored data.

If SerpApi fails, the `POST` response includes a `search_id` and the failed search is saved. Inspect it with `GET /searches/:id`.

### Development

Run the tests and lint:

```sh
bin/rails test
bundle exec rubocop
```

Tests use stubs and do not require a SerpApi key or make live requests.
