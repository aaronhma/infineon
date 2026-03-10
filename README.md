# ARGUS: Autonomous Real-time Guardian for Ubiquitous Safety

## Winter 2026 Infineon Special Project

> Argus or Argos Panoptes (Ancient Greek: Ἄργος Πανόπτης, "All-seeing Argos") is a many-eyed giant in Greek mythology. Known for his perpetual vigilance, he served the goddess Hera as a watchman. His most famous task was guarding Io, a priestess of Hera, whom Zeus had transformed into a heifer. Argus's constant watch, with some of his eyes always open, made him a formidable guardian.
>
> - [Source: Wikipedia](https://en.wikipedia.org/wiki/Argus_Panoptes)

## About

This research project was conducted during the Winter 2026 academic quarter at [De Anza College](https://www.deanza.edu/catalog/courses/outline.html?course=engrd077&y=2025-2026).

We're making driving safe for everyone.

## Project Abstract & Report

Click [here to read our REPORT](REPORT.md).

## Project Structure

We use a monorepo structure, so all project components can be in one repo.

## [Firmware](firmware/README.md)

**Folder:** [`firmware`](firmware/README.md)

- *Built with:* Infineon ModusToolbox

The firmware that runs on the Infineon AI board.

## [iOS Project](iOS/)

**Folder:** [`iOS`](iOS/)

- *Built with:* Swift, SwiftUI, Supabase

The companion iOS app allows users to keep track of driver profiles, previous infractions, and other features.

## [Research](research/)

**Folder:** [`iOS`](research/README.md)

- *Built with:* Python

All the AI/ML code running on the Raspberry Pi.

## [Supabase Database](supabase/)

**Folder:** [`supabase`](supabase/)

- *Built with:* Supabase, PostgreSQL

This folder contains the Supabase PostgreSQL table and bucket setup, along with Supabase Edge functions and future migrations.

## [Helper Scripts](scripts/README.md)

**Folder:** [`scripts`](scripts/README.md)

- *Built with:* JavaScript, Bun

This folder contains helpful functions for the project.

## Attributions

**Researchers:**

- Aaron Ma, Team Leader
- Anton Bogatyrev
- Mobin Norouzi
- Peter Davis, Hardware Lead
- Sheel Shah

**Special thanks to:**

- Professor Saied Rafati, De Anza College Engineering

## © Copyright 2026 Aaron Ma. All rights reserved.
