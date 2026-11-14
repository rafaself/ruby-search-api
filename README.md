# Search API

A small API-only Ruby on Rails application using SQLite. It stores search
requests and exposes JSON endpoints; it does not call SerpApi.

## Structure

- `app/controllers/` contains the API base controller and endpoint actions.
- `app/models/` contains Active Record models backed by SQLite.
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
`created_at`, and `updated_at` fields. New searches start with status `pending`.
The allowed statuses are `pending`, `processing`, `completed`, and `failed`;
the API currently creates searches as pending and does not run a provider or
change their status.

Create a search (the client supplies `query`; status is assigned by the server):

```sh
curl -X POST http://localhost:3000/searches \
  -H 'Content-Type: application/json' \
  -d '{"search":{"query":"ruby on rails"}}'
```

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

## Request lifecycle

1. Rails matches the HTTP verb and path in `config/routes.rb` to a controller
   action.
2. `SearchesController` reads permitted request parameters, asks Active Record
   to create/find/delete a `Search`, and renders the result as JSON.
3. On `POST`, the `status` column defaults to `pending`. Active Record runs the
   model validations and writes the row only if it is valid. Active Record sets
   the timestamps, and SQLite assigns the ID. Failed validations return `422`
   and their error messages.
4. `GET` actions load existing rows through Active Record. A missing ID is
   converted by `ApplicationController` into a JSON `404` response.
5. `DELETE` removes the row through Active Record and returns an empty `204`
   response.

## Run locally

From the project directory:

```sh
bundle install
bin/rails db:prepare
bin/rails server
```

Check the endpoint at `http://localhost:3000/health`:

```sh
curl http://localhost:3000/health
```

It returns `{"status":"ok"}`. The development database is stored at
`storage/development.sqlite3`.
