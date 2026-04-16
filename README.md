# Headless Dam (Digital Asset Management)
Cloud-agnostic Headless DAM using Fastly IO for dynamic asset transformation and metadata-driven delivery.

## Core Architecture
- **Storage:** Multi-cloud support (S3, Azure Blob, Google Cloud Storage).
- **Transformation:** Fastly Image Optimizer (IO).
- **Metadata:** PostgreSQL + Typesense for sub-second search.

## Setup Instructions

### 1. Storage Configuration
Configure your bucket policy to allow Fastly to read assets.
- [ ] Set up AWS S3 IAM User / Azure SAS Token.
- [ ] Configure Origin Shielding in Fastly.

### 2. Environment Variables
Create a `.env` file in `apps/api-service`:
- `FASTLY_IO_KEY`: Your Fastly API Token.
- `DATABASE_URL`: Postgres connection string.
- `STORAGE_PROVIDER`: 'aws' | 'azure' | 'gcp'

### 3. Running Locally
```bash
npm install
npm run dev