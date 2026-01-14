# Winter 2026 Infineon Special Project

## Project Structure

We use a monorepo structure, so all project components can be in one repo.

## [iOS Project](iOS/)

**Folder:** [`iOS`](iOS/)

- *Built with:* Swift, SwiftUI, Supabase

The companion iOS app allows users to keep track of driver profiles, previous infractions, and other features.

## [Supabase Database](supabase/)

**Folder:** [`supabase`](supabase/)

- *Built with:* Supabase, PostgreSQL

This folder contains the Supabase PostgreSQL table and bucket setup, along with Supabase Edge functions and future migrations.

## [Helper Scripts](scripts/README.md)

**Folder:** [`scripts`](scripts/README.md)

- *Built with:* JavaScript, Bun

This folder contains helpful functions for the project.
