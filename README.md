# Search API

A small API-only Ruby on Rails application using SQLite.

## Structure

- `app/controllers/` contains the API base controller and health endpoint.
- `app/models/application_record.rb` is the shared base class for future Active Record models.
- `config/routes.rb` maps HTTP requests to controller actions.
- `config/database.yml` configures SQLite for each Rails environment.
- `config/application.rb` loads the Rails components used by this API.
- `Gemfile` lists Rails, SQLite, and Puma.

## Ruby concepts

`SearchApi` is a module that namespaces the application. Controllers are
classes: `HealthController` inherits from `ApplicationController`. Its `show`
method is an action, and `render json:` converts a Ruby hash into a JSON
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
