---
# rally-gvkf
title: Move dark mode browser persistence into Rally
status: todo
type: task
priority: normal
tags:
    - boundary-cleanup
    - browser
created_at: 2026-06-05T19:20:33Z
updated_at: 2026-06-05T19:21:15Z
parent: rally-kobq
---

## Problem

Scoreboard app code still owns generic dark-mode browser mechanics: reading device preference, booting the current value, applying it to the document, and persisting the selected value. The actual UI control can stay application-owned because the shell decides how and where users toggle theme, but the browser/runtime mechanics are not Scoreboard domain behavior.

## Intended direction

Rally should own the reusable dark-mode runtime plumbing:

- detect device/system dark mode when no persisted value exists;
- read/write the persisted preference;
- apply the current mode to the document/root element;
- expose small browser/runtime helpers and generated boot wiring so app shells can render a product-owned toggle without owning storage mechanics.

The app should own:

- whether a toggle is shown;
- shell styling and button placement;
- the user-facing message/control that flips the setting.

## Acceptance criteria

- Scoreboard root/app shell no longer owns dark-mode storage or document-application mechanics.
- App shell still owns the dark-mode toggle UI and passes user intent into Rally-owned runtime helpers.
- Existing public/admin shell behavior and browser smoke still pass.
- The implementation stays template/runtime-sized and does not become a general theme system.

## Scope Clarification

This is only about abstracting how dark mode is turned on/off and stored. It is not a theme framework.

Rally should provide the storage/application mechanics. The application still decides what the UI control looks like and what dark mode means in its CSS.
