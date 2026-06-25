# Capri DAM (Digital Asset Management)

A modern, high-performance Capri DAM built with a decoupled architecture. This platform utilizes **Ruby on Rails** for 
the management engine and **React** for a dynamic, responsive user interface.

---

## 🛠 Tech Stack

- **Backend:** Ruby on Rails 7 (API & Business Logic)
- **Frontend:** React 19 & Material UI v9
- **Ruby:** 4.0.3
- **Database:** PostgreSQL 14+
- **Styling:** Emotion 11 (MUI Engine)

---

##  Getting Started

The project uses a `Makefile` to automate system dependencies and application configuration. Follow these steps in order.

### 1. Initial System Bootstrap
If you are setting up on a new machine, run this to install the required system libraries (Node, Yarn, Ruby Version Manager, and Database Engine).

```bash
make bootstrap
#Note: After this completes, you must restart your terminal or run `source ~/.zshrc` to activate the new Ruby environment.
```
### 2. Application Setup
This command installs all Ruby gems, JavaScript packages, creates the database, and prepares the internal Rails structure.
```bash
make setup
```

### 3. Launch Development Environment
Run the following to start the Rails server and the React compiler simultaneously:

```bash
yarn build && make dev 
```
### Available CommandsCommand

`make bootstrap`	Installs system-level packages and Ruby 4.0.3.

`make setup`	Installs dependencies and prepares the database.

`yarn build && make dev`	Starts the application and JS watcher.

`make db-setup`	Specifically repairs or resets the PostgreSQL database.

`make clean`	Wipes temporary logs and asset builds.

`make help`	Displays a full list of available automation targets.