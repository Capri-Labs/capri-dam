# System Architecture

Headless DAM is designed for scale, flexibility, and enterprise compliance. By decoupling the asset management logic into a robust API and background processing layer, it can serve as the single source of truth for media across an organization.

## 1. The Hybrid Monolith
Rather than managing a completely separate SPA (Single Page Application) repository and a backend API repository, this project utilizes a "Hybrid Monolith" approach.
* **Routing:** Handled by Ruby on Rails.
* **View Delivery:** Rails serves standard HTML views containing Hotwire/Turbo elements.
* **Interactivity:** React is mounted into specific DOM nodes via `application.js` based on `data-view` attributes. This provides the snappy UX of an SPA without the complex state-management overhead of client-side routing.

## 2. Data & Storage Layer
* **PostgreSQL:** The primary relational database handling RBAC, metadata, folder structures, and audit logs.
* **ActiveStorage:** Abstracts the actual file storage. Development uses local disk, while production is designed to plug directly into AWS S3, Google Cloud Storage, or Azure Blob Storage, paired with a CDN.

## 3. Asynchronous Processing (Sidekiq)
Enterprise DAMs deal with massive files (4K video, high-res RAW images). To prevent web server timeouts, all heavy lifting is pushed to background workers.
The Sidekiq configuration uses strict **Queue Weighting**:
1. `mailers` & `notifications` (High Priority)
2. `default` & `workflow` (Standard Priority)
3. `metadata`, `reports`, `ingest` (Heavy / Low Priority)

This topology guarantees that a 10,000-image bulk upload will never delay a user's password reset email.

## 4. Security & Access (RBAC)
Access is not handled at a simple "Admin vs User" level.
* **Users** belong to **UserGroups**.
* **Folders** have **Policies** attached to them.
* Access is resolved by checking if a user's group has explicit permission (Read, Write, Delete) for a specific folder path.

## 5. Directory Structure
* `app/controllers/api/v1/`: Endpoints consumed by React.
* `app/controllers/admin/`: System ops and reporting endpoints.
* `app/javascript/components/`: The React frontend, organized by domain (`/Bin`, `/Folders`, `/Admin`).
* `app/jobs/`: ActiveJob workers for Sidekiq processing.