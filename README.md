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
- `Gemfile` lists Rails, SQLite, and Puma.

## Ruby concepts

`SearchApi` is a module that namespaces the application. Controllers are
classes: `SearchesController` inherits from `ApplicationController`, and each
action handles one route. `Search` inherits from `ApplicationRecord`, which
connects it to the `searches` table through Rails naming conventions. Active
Record validates model attributes and reads or writes rows in SQLite; for
example, `Search.find(id)` loads a row and `search.save` validates and persists
a new record. `render json:` turns a model or Ruby hash into a JSON response.

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

## Request lifecycle

1. Rails matches the HTTP verb and path in `config/routes.rb` to a controller
   action.
2. `SearchesController` permits only the query and saves a pending search.
   Active Record validates it before any provider call. Invalid queries return
   `422` without saving a record or making an HTTP request.
3. `Search#perform!` saves `processing`, then invokes `SerpApiClient#search`.
   The client calls `https://serpapi.com/search.json` with `engine=google`, the
   query, the environment API key, and `async=false`.
4. The client checks the HTTP status, parses the JSON, validates the response,
   and extracts up to 10 organic results. Active Record saves those results and
   `completed` together. On an expected provider failure, it saves `failed` and
   re-raises the safe client error for the controller to render.
5. Active Record handles SQL and JSON conversion, sets timestamps, and loads
   SQLite's assigned ID. `GET` actions load rows through Active Record without
   re-running searches. A missing ID is
   converted by `ApplicationController` into a JSON `404` response.
6. `DELETE` removes the row through Active Record and returns an empty `204`
   response.

## Design decisions

- `SerpApiClient` uses Ruby's available `Net::HTTP` and JSON libraries, so no new
  gems are needed. Its credentials come from `SERPAPI_API_KEY`; they are never
  accepted from the API caller or stored in the search row.
- The client uses HTTPS with certificate verification, a fixed provider host,
  and URL-encoded query parameters. It does not follow redirects. Timeouts are
  5 seconds for connection and writes, and 30 seconds for reads; these are
  operation timeouts, not a total request deadline. Automatic retries are
  disabled to avoid extra provider requests.
- Explicit `Search#perform!` orchestration keeps controllers thin. Avoiding
  model callbacks means saving or reading a search does not implicitly make a
  network request. Each status update is committed before the next step; the
  HTTP call does not hold a database transaction or SQLite write lock.
- A synchronous call keeps the flow small and returns results immediately, but
  occupies a Rails request worker until the provider responds or times out.
  A process interruption may leave a record in `processing`.
- Only expected transport/provider failures are handled. Database or programming
  errors propagate normally. The API retains failed records for inspection,
  with no persistent provider error-message column.
- The client requires successful response metadata and rejects malformed JSON,
  invalid result types, and API errors even when HTTP is `200`. SerpApi's
  documented `Success` with `organic_results_state: "Fully empty"` and an
  error message is treated as a completed search with no results. See the
  [Google Search API](https://serpapi.com/search-api) and
  [status/error documentation](https://serpapi.com/api-status-and-error-codes).

## Run locally

From the project directory:

```sh
bundle install
bin/rails db:prepare
export SERPAPI_API_KEY='your-serpapi-api-key'
bin/rails server
```

Set the key in the server process environment. The app does not load `.env`
files automatically. The migrations add JSON storage to existing searches
with an empty array default, preserving their current statuses.

Check the endpoint at `http://localhost:3000/health`:

```sh
curl http://localhost:3000/health
```

It returns `{"status":"ok"}`. The development database is stored at
`storage/development.sqlite3`.

## Tests

```sh
bin/rails test
```

The tests use fake HTTP responses and injected clients to cover result
extraction, status persistence, error handling, and the API lifecycle. They do
not make live SerpApi calls or require a real API key.
