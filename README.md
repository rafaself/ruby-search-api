# Search API

A small API-only Ruby on Rails application using SQLite. It stores search
requests, synchronously calls SerpApi's Google Search endpoint, and exposes
the saved organic results as JSON.

## Structure

- `app/controllers/` contains the API base controller and endpoint actions.
- `app/models/` contains Active Record models backed by SQLite.
- `app/services/serp_api_client.rb` handles SerpApi HTTP requests and responses.
- `db/migrate/` contains database schema migrations.
- `config/routes.rb` maps HTTP requests to controller actions.
- `config/database.yml` configures SQLite for each Rails environment.
- `config/application.rb` loads the Rails components used by this API.
- `Gemfile` lists the application and development dependencies.

## Search endpoints

The API accepts and returns JSON. A search has `id`, `query`, `status`,
`results`, `created_at`, and `updated_at` fields. New searches start with status
`pending`, transition to `processing` before the HTTP call, and finish as
`completed` or `failed`. The POST waits for this operation to finish.

Create a search (the client supplies `query`; status and results are assigned
by the server):

```sh
curl -X POST http://localhost:3000/searches \
  -H 'Content-Type: application/json' \
  -d '{"search":{"query":"ruby on rails"}}'
```

A successful response is `201 Created` with the completed search:

```json
{
  "id": 1,
  "query": "ruby on rails",
  "status": "completed",
  "results": [
    {
      "position": 1,
      "title": "Ruby on Rails",
      "link": "https://rubyonrails.org/",
      "snippet": "A web application framework."
    }
  ],
  "created_at": "2026-11-14T12:00:00.000Z",
  "updated_at": "2026-11-14T12:00:01.000Z"
}
```

`results` is a JSON array, not an encoded JSON string. It contains at most 10
organic results in provider order, each with `position`, `title`, `link`, and
`snippet`. Missing fields are `null`. Ads and other result sections are
discarded. Successful searches with no organic matches return `results: []`.

List searches, newest first:

```sh
curl http://localhost:3000/searches
```

Fetch one search or delete it:

```sh
curl http://localhost:3000/searches/1
curl -X DELETE http://localhost:3000/searches/1
```

Creation returns `201 Created`; list and show return `200 OK`; deletion
returns `204 No Content`. Invalid attributes return `422 Unprocessable Entity`
with an `errors` array. Missing required request parameters return `400 Bad
Request`, and unknown IDs return `404 Not Found`; both use the same `errors`
array response shape.

Provider failures still save the search with status `failed` and `results: []`.
The POST returns an error status and the ID of that search:

```json
{"errors":["Search provider timed out."],"search_id":1}
```

| Failure | HTTP status |
| --- | --- |
| Connection, read, or write timeout | `504 Gateway Timeout` |
| Provider HTTP or API error, network/TLS failure, invalid response | `502 Bad Gateway` |
| Missing or blank `SERPAPI_API_KEY` | `503 Service Unavailable` |

Error messages do not contain provider bodies, credential-bearing URLs, or
raw network exceptions. Fetch the saved search with `GET /searches/:id` using
the returned `search_id`. GET and DELETE operate on stored data and do not call
SerpApi. Existing pending searches are not automatically executed.

## Provider behavior

`SERPAPI_API_KEY` is read from the server environment and is never accepted in
request parameters or stored in the database. The client uses HTTPS, sends a
synchronous Google Search request, does not follow redirects, and does not
retry. Connection and write timeouts are 5 seconds; the read timeout is 30
seconds.

Provider failures save a search with status `failed` and `results: []`. The
POST response includes its `search_id`; fetch it with `GET /searches/:id`.
Errors omit provider response bodies and raw network exceptions. GET and DELETE
use saved data and do not call SerpApi. Existing pending searches are not
automatically executed.

## Run locally

Ruby 3.4.12 and Bundler are specified by `.ruby-version` and `Gemfile.lock`.
From the project directory, install dependencies and prepare SQLite:

```sh
bundle install
bin/rails db:prepare
export SERPAPI_API_KEY='your-serpapi-api-key'
bin/rails server
```

Set the key in the server process environment before starting the server. The
app does not load `.env` files automatically. The development database is
`storage/development.sqlite3`.

Check the endpoint at `http://localhost:3000/health`:

```sh
curl http://localhost:3000/health
```

It returns `{"status":"ok"}`.

## Tests

```sh
bin/rails test
```

The tests use fake HTTP responses and injected clients to cover result
extraction, status persistence, endpoints, and failure handling. Unexpected
HTTP calls fail in the fake client, so the suite does not make live SerpApi
requests, consume API credits, or require an API key.

## Lint

The project uses the RuboCop Rails Omakase profile:

```sh
bundle exec rubocop
```
