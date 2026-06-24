# Variables
RAILS = ./bin/rails
BUNDLE = bundle
YARN = yarn
RUBY_VERSION = 4.0.3

.PHONY: help bootstrap check-system install db-setup setup dev \
        swagger-docs graphql-schema graphql-docs api-docs \
        install-hooks check-api-specs check-graphql-docs

help: ## Show this help message
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Force install system dependencies (macOS/Homebrew only)
	@echo "--- 1. Bootstrapping System Packages ---"
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew not found. Install it first."; exit 1; }
	brew install redis rbenv ruby-build node yarn exiv2 pkg-config postgresql@14
	@echo "--- 2. Ensuring Ruby $(RUBY_VERSION) is installed ---"
	rbenv install -s $(RUBY_VERSION)
	rbenv global $(RUBY_VERSION)
	@echo "--- 3. Installing Global Rails Gem ---"
	# We install rails globally so we can run 'rails new' to fix the project structure
	gem install rails sidekiq redis --no-document
	@echo "\033[33mSystem packages installed. If this is your first time, run 'source ~/.zshrc' then 'make setup'\033[0m"

check-system: ## Verify if we are on the right Ruby and have Yarn
	@echo "--- Checking Environment ---"
	@if [ "$$(ruby -v | grep $(RUBY_VERSION))" = "" ]; then \
		echo "\033[31mWrong Ruby version. Expected $(RUBY_VERSION). Running bootstrap...\033[0m"; \
		make bootstrap; \
		exit 1; \
	fi
	@command -v rails >/dev/null 2>&1 || { echo "Rails gem missing. Installing..."; gem install rails --no-document; }
	@command -v $(YARN) >/dev/null 2>&1 || { echo "Yarn missing. Running bootstrap..."; make bootstrap; exit 1; }
	@echo "\033[32mEnvironment OK.\033[0m"

repair-lockfile: ## Force update the lockfile for modern Ruby
	rm -f Gemfile.lock
	gem install bundler
	$(BUNDLE) install

install: check-system ## Install Ruby gems and JS packages
	@echo "--- Installing App Dependencies ---"
	gem install bundler --no-document
	$(BUNDLE) install || { echo "Retrying with lockfile repair..."; make repair-lockfile; }
	$(YARN) install
	$(YARN) add react react-dom @mui/material @emotion/react @emotion/styled @mui/icons-material

upload-workers: ## Manual start for just the workers (if needed)
	@echo "--- Starting Ingest Engine ---"
	bundle exec sidekiq -C config/sidekiq.yml

auth-setup: ## Initialize Devise if not already present
	@if [ ! -f config/initializers/devise.rb ]; then \
		echo "--- Initializing Devise Authentication ---"; \
		$(BUNDLE) exec rails generate devise:install; \
	fi
	@if [ ! -f app/models/user.rb ]; then \
		echo "--- Generating User Model ---"; \
		$(BUNDLE) exec rails generate devise User; \
	fi

test-setup: ## Initialize rspec if not already present
	@if [ ! -d "spec" ]; then \
		echo "--- Initializing rspec setup ---"; \
		$(BUNDLE) exec rails generate rspec:install; \
		echo "--- Initializing rspec finished ---"; \
	else \
		echo "--- RSpec is already initialized. Skipping. ---"; \
	fi

seed: ## Populate the database with default admin user
	@echo "--- Seeding Database ---"
	./bin/rails db:seed
	@echo "Default admin user has been created"

setup-oauth: ## Install and configure Doorkeeper for OAuth2
	@echo "--- Installing Doorkeeper ---"
	bundle add doorkeeper
	bundle exec rails generate doorkeeper:install
	bundle exec rails generate doorkeeper:migration
	@echo "--- Applying OAuth Migrations ---"
	bundle exec rails db:migrate

db-setup: auth-setup ## Create and migrate the database
	@echo "--- Setting up Postgres ---"
	@# Check if Postgres is running via Homebrew
	@if ! brew services list | grep -q "postgresql@14.*started"; then \
	   echo "Postgres is not running. Starting it..."; \
	   brew services start postgresql@14; \
	   sleep 5; \
	fi
	@if [ ! -f $(RAILS_EXE) ]; then \
	   echo "\033[31m$(RAILS_EXE) not found. Regenerating Rails structure...\033[0m"; \
	   rails new . --force --database=postgresql --javascript=esbuild --skip-bundle; \
	   chmod +x bin/*; \
	fi
	@chmod +x bin/rails
	$(RAILS) db:create
	$(RAILS) db:prepare
	$(MAKE) seed
	$(MAKE) test-setup

setup: install db-setup ## The 'One Command' to rule them all
	@echo "\033[32m--- Headless DAM Setup Complete ---\033[0m"
	@echo "Run 'make dev' to start the server, workers, and redis."

swagger-docs: ## Generate Swagger/OpenAPI REST docs (spec/requests/api → swagger/v1/swagger.yaml)
	@echo "--- Preparing test database ---"
	RAILS_ENV=test bundle exec rails db:test:prepare
	@echo "--- Generating OpenAPI Spec (spec/requests/api/**/*_spec.rb → swagger/v1/swagger.yaml) ---"
	RAILS_ENV=test RUN_API_DOCS=1 RSWAG_DRY_RUN=0 bundle exec rails rswag:specs:swaggerize
	@echo "\033[32mDone. View at: http://localhost:3000/api/rest\033[0m"

graphql-schema: ## Dump the live GraphQL SDL to swagger/graphql/schema.graphql
	@echo "--- Dumping GraphQL SDL schema ---"
	@mkdir -p swagger/graphql
	RAILS_ENV=development bundle exec rails graphql:schema:dump
	@echo "\033[32mSDL written to swagger/graphql/schema.graphql\033[0m"

graphql-docs: graphql-schema ## Generate SpectaQL HTML docs → public/graphql-docs/index.html
	@echo "--- Generating GraphQL HTML docs (SpectaQL) ---"
	@mkdir -p public/graphql-docs
	./node_modules/.bin/spectaql spectaql-config.json
	@echo "\033[32mDone. View at: http://localhost:3000/api/graphql\033[0m"

api-docs: swagger-docs graphql-docs ## Regenerate BOTH REST (Swagger) and GraphQL (SpectaQL) docs

install-hooks: ## Install the stale-docs pre-commit git hook
	@echo "--- Installing pre-commit hook ---"
	@chmod +x bin/check-docs-freshness
	@cp bin/check-docs-freshness .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "\033[32mPre-commit hook installed. Commits that change controllers or GraphQL\033[0m"
	@echo "\033[32msource without regenerating docs will be blocked.\033[0m"

check-graphql-docs: ## Verify swagger/graphql/schema.graphql and public/graphql-docs/index.html exist
	@echo "--- Checking for generated GraphQL docs ---"
	@missing=0; \
	if [ ! -f "swagger/graphql/schema.graphql" ]; then \
	  echo "\033[31mMISSING: swagger/graphql/schema.graphql — run: make graphql-schema\033[0m"; \
	  missing=$$((missing+1)); \
	fi; \
	if [ ! -f "public/graphql-docs/index.html" ]; then \
	  echo "\033[31mMISSING: public/graphql-docs/index.html — run: make graphql-docs\033[0m"; \
	  missing=$$((missing+1)); \
	fi; \
	if [ $$missing -gt 0 ]; then \
	  echo "\033[31m$$missing GraphQL doc artifact(s) missing. Run: make graphql-docs\033[0m"; \
	  exit 1; \
	else \
	  echo "\033[32mGraphQL docs are present and up to date.\033[0m"; \
	fi

check-api-specs: ## Verify every app/controllers/api/v1/*_controller.rb has a matching spec
	@echo "--- Checking for missing API request specs ---"
	@missing=0; \
	for ctrl in app/controllers/api/v1/*_controller.rb; do \
	  base=$$(basename $$ctrl _controller.rb); \
	  spec="spec/requests/api/v1/$${base}_spec.rb"; \
	  if [ ! -f "$$spec" ]; then \
	    echo "\033[31mMISSING spec: $$spec\033[0m"; \
	    missing=$$((missing+1)); \
	  fi; \
	done; \
	if [ $$missing -gt 0 ]; then \
	  echo "\033[31m$$missing controller(s) are missing request specs. Run: make swagger-docs\033[0m"; \
	  exit 1; \
	else \
	  echo "\033[32mAll API controllers have request specs.\033[0m"; \
	fi

dev: ## Start the full engine (Server + Ingest Workers)
	@echo "--- Switching to development environment ---"
	@echo "--- Launching Headless DAM Ecosystem ---"
	RAILS_ENV=development ./bin/dev

all-tests: ## Run all RSpec tests
	@echo "--- Running Tests ---"
	bundle exec rspec

# ===========================================================================
# TEST & COVERAGE
# ===========================================================================
# Quick reference:
#   make test                 -> full backend RSpec suite (unit + integration + system)
#   make test-frontend        -> Jest unit/component tests
#   make coverage-backend     -> Backend coverage (RSpec + SimpleCov)
#   make coverage-frontend    -> Frontend coverage (Jest + Istanbul)
#   make e2e-backend          -> Backend E2E coverage (Coverband, runtime)
#   make e2e-frontend         -> Frontend E2E coverage (Playwright + Istanbul)
#   make coverage             -> backend + frontend unit/integration coverage
#   make e2e                  -> backend + frontend E2E coverage
#   make test-all             -> everything

.PHONY: test test-frontend test-graphql coverage-backend coverage-frontend e2e-backend \
        e2e-frontend coverage e2e test-all playwright-install test-api-docs

test: ## Run the full backend RSpec suite (models, requests, system)
	@echo "--- Preparing test database ---"
	RAILS_ENV=test bundle exec rails db:test:prepare
	@echo "--- Backend: RSpec suite ---"
	bundle exec rspec

test-api-docs: ## Run the rswag OpenAPI/Swagger doc specs (excluded from the default run)
	@echo "--- Preparing test database ---"
	RAILS_ENV=test bundle exec rails db:test:prepare
	@echo "--- Backend: rswag API-doc specs ---"
	RUN_API_DOCS=1 bundle exec rspec spec/requests --format progress 2>&1

test-graphql: ## Run the GraphQL endpoint request specs
	@echo "--- Preparing test database ---"
	RAILS_ENV=test bundle exec rails db:test:prepare
	@echo "--- Backend: GraphQL request specs ---"
	bundle exec rspec spec/requests/graphql_spec.rb --format documentation 2>&1

test-frontend: ## Run the frontend Jest unit & component tests
	@echo "--- Frontend: Jest ---"
	$(YARN) jest

coverage-backend: ## Backend coverage (RSpec + SimpleCov) -> coverage/backend/index.html
	@echo "--- Preparing test database ---"
	RAILS_ENV=test bundle exec rails db:test:prepare
	@echo "--- Backend coverage (RSpec + SimpleCov) ---"
	COVERAGE=true bundle exec rspec
	@echo "\033[32mHTML:\033[0m coverage/backend/index.html  \033[32mXML:\033[0m coverage/backend/coverage.xml"

coverage-frontend: ## Frontend coverage (Jest + Istanbul) -> coverage-frontend/unit/index.html
	@echo "--- Frontend coverage (Jest + Istanbul) ---"
	$(YARN) jest --coverage
	@echo "\033[32mHTML:\033[0m coverage-frontend/unit/index.html"

playwright-install: ## Install the Playwright browser binaries (one-time)
	$(YARN) playwright install --with-deps chromium

e2e-frontend: ## Frontend E2E coverage (Playwright + Istanbul) -> coverage-frontend/e2e
	@echo "--- Frontend E2E (Playwright + Istanbul) ---"
	@echo "Requires a running server (make dev) and browsers (make playwright-install)."
	$(YARN) playwright test
	@echo "\033[32mIstanbul report:\033[0m coverage-frontend/e2e/index.html"

e2e-backend: ## Backend E2E coverage (Coverband runtime) -> /admin/coverband
	@echo "--- Backend E2E (Coverband runtime) ---"
	@echo "Exercise the running server (e.g. 'make e2e-frontend'), then summarise:"
	RAILS_ENV=development bundle exec rake coverband:report
	@echo "\033[32mDashboard:\033[0m http://localhost:3000/admin/coverband (admin login)"

coverage: coverage-backend coverage-frontend ## Run backend + frontend unit/integration coverage

e2e: e2e-frontend e2e-backend ## Run frontend + backend E2E coverage (server must be running)

test-all: coverage e2e ## Run the entire test + coverage matrix

clean: ## Remove logs, temp files and compiled assets
	$(RAILS) log:clear tmp:clear
	rm -rf public/assets
	rm -rf app/assets/builds/*