# Variables
RAILS = ./bin/rails
BUNDLE = bundle
YARN = yarn
RUBY_VERSION = 4.0.3

.PHONY: help bootstrap check-system install db-setup setup dev

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Force install system dependencies (macOS/Homebrew only)
	@echo "--- 1. Bootstrapping System Packages ---"
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew not found. Install it first."; exit 1; }
	brew install rbenv ruby-build node yarn exiv2 pkg-config postgresql@14
	@echo "--- 2. Ensuring Ruby $(RUBY_VERSION) is installed ---"
	rbenv install -s $(RUBY_VERSION)
	rbenv global $(RUBY_VERSION)
	@echo "--- 3. Installing Global Rails Gem ---"
	# We install rails globally so we can run 'rails new' to fix the project structure
	gem install rails --no-document
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
	echo "--- Initializing rspec setup ---";
	$(BUNDLE) exec rails generate rspec:install;
	echo "--- Initializing rspec finished ---";

seed: ## Populate the database with default admin user
	@echo "--- Seeding Database ---"
	./bin/rails db:seed
	@echo "Default admin user has been created"

db-setup: auth-setup seed test-setup ## Create and migrate the database
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

setup: install db-setup ## The 'One Command' to rule them all
	@echo "\033[32m--- Headless DAM Setup Complete ---\033[0m"
	@echo "Run 'make dev' to start."

dev: ## Start the engine
	./bin/dev

all-tests: ## Run all RSpec tests
	@echo "--- Running Tests ---"
	bundle exec rspec

clean: ## Remove logs, temp files and compiled assets
	$(RAILS) log:clear tmp:clear
	rm -rf public/assets
	rm -rf app/assets/builds/*