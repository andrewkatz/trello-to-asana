# Trello to Asana

A script that migrates a Trello board to Asana.

It will:

- Create a new Asana project
- Import each Trello list as a section in the project
- Create a task for each card
- Create a subtask for each checklist item

# Running it

You'll need the following as environment variables:

```sh
export TRELLO_APP_KEY=your-app-key
export TRELLO_APP_TOKEN=your-app-token
export ASANA_TOKEN=your-asana-token
```

Then to install and run it:

```sh
bundle install
bundle exec ruby migrate.rb
```

It will prompt you for the Trello board you wish to migrate.
