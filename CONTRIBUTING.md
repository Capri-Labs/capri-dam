# Contributing to Capri DAM

First off, thank you for considering contributing to Capri DAM! It's people like you that make open-source software great.

## Code of Conduct
By participating in this project, you are expected to uphold a welcoming, inclusive, and professional environment.

## Development Setup

### Prerequisites
* Ruby (check `.ruby-version`)
* Node.js & Yarn
* PostgreSQL
* Redis (Required for Sidekiq)

### Local Installation
1. Fork the repo and clone it locally.
2. Run `bundle install` and `yarn install`.
3. Setup the database: `rails db:setup`.
   4. Start the development servers:
      ```bash
      # In terminal (Rails + React compilation)
      yarn build && make dev
      ```